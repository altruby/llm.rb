# frozen_string_literal: true

require "setup"
require "timeout"

##
# The ractor's half of the window's contract.
#
# `spec/function/window_spec.rb` covers the window's three cases unit by
# unit, with a thread standing in for the tool. This covers the window's
# second caller, where the tool runs inside a ractor, and the cases are
# the same three:
#
# - an interrupt that arrives while the tool runs reaches the tool's own
#   `rescue`, and its value comes back;
# - an interrupt that arrives before the tool runs is held until it does,
#   and reaches the tool's `rescue` the same way, rather than being
#   answered early with `{cancelled: true}` for a call that never ran;
# - a tool that does not rescue is answered with `{cancelled: true}`,
#   because the ractor's own `rescue` answers it - an exception does not
#   cross a ractor boundary, so the answer to an interrupted call is this
#   strategy's own.
#
# **The held case detects the race rather than ordering it.** Nothing in
# that example orders the interrupt against the ractor reaching
# `running!`, and the tool cannot say that it got there, because a tool
# that signals from inside its own call is the first case, not that one.
# A red run there can mean a scheduler as easily as a broken window; the
# other two can only mean the window.
#
# **"Now" has to cross a ractor boundary.** The window's own spec hands
# its tool a Queue, because both ends of that handover are threads the
# example made. Here the example runs on the main ractor and drives a
# task whose tool runs in another one, so the handover is made with the
# one object that crosses a ractor boundary: a ractor. The tool is
# handed the ractor the example itself runs on and signals it when it is
# running, and the example waits on `Ractor.receive` for that message,
# which blocks until it arrives. No example sleeps to find out where the
# call has got to: `signal` is the "now", and the cases that need one use
# it.
#
# **The tool holds.** A tool signals and then sleeps, so an interrupt is
# delivered while the tool is inside its own call, rather than after it
# has returned, where the window makes the interrupt a no-op.
RSpec.describe LLM::Function::Ractor::Job do
  ##
  # The parser is compared as it is written rather than as CI spells it,
  # which is `JSON`, so this is not a guard that always skips.
  before do
    skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  ##
  # The ractor these examples run on, and the one a tool is handed so
  # that it can say that it is running.
  let(:port) { Ractor.current }

  ##
  # The tool's message, or a failure rather than a hang if the ractor
  # never gets as far as sending it.
  def signal
    Timeout.timeout(5) { Ractor.receive }
  end

  describe "an interrupt while the tool runs" do
    let(:tool_class) do
      Class.new(LLM::Tool) do
        name "interruptible"

        def call(port:)
          port.send([:running])
          sleep 10
          {"ok" => true}
        rescue LLM::Interrupt
          {"ok" => true, "interrupted" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {port: port}
      end
    end

    let(:task) { function.task(:ractor) }

    it "reaches the tool's own rescue" do
      task.spawn
      ##
      # Sent from inside the tool's call, so the interrupt is delivered
      # to a tool that is running. This is the case the ractor already
      # delivered, and the case the window must not break.
      signal
      task.interrupt!
      expect(Timeout.timeout(5) { task.wait.to_h }).to eq(
        id: "call_1",
        name: "interruptible",
        value: {"ok" => true, "interrupted" => true}
      )
    end
  end

  describe "an interrupt before the tool runs" do
    let(:tool_class) do
      Class.new(LLM::Tool) do
        name "held"

        def call
          sleep 10
          {"ok" => true}
        rescue LLM::Interrupt
          {"ok" => true, "interrupted" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_2"
        fn.arguments = {}
      end
    end

    let(:task) { function.task(:ractor) }

    it "is held until the tool runs, and reaches the tool's own rescue" do
      task.spawn
      ##
      # Delivered before the tool has had a chance to open its window, so
      # the window is idle when it arrives. Nothing may answer it in the
      # meantime: a tool that saves its work, or closes what it opened,
      # when it is cancelled is told by its own `rescue`, and loses it if
      # the call is answered early instead.
      task.interrupt!
      expect(Timeout.timeout(5) { task.wait.to_h }).to eq(
        id: "call_2",
        name: "held",
        value: {"ok" => true, "interrupted" => true}
      )
    end
  end

  describe "an interrupt and a tool that does not rescue" do
    let(:tool_class) do
      Class.new(LLM::Tool) do
        name "brittle"

        def call(port:)
          port.send([:running])
          sleep 10
          {"ok" => true}
        end
      end
    end

    let(:function) do
      tool_class.function.dup.tap do |fn|
        fn.id = "call_3"
        fn.arguments = {port: port}
      end
    end

    let(:task) { function.task(:ractor) }

    it "answers that the call was cancelled" do
      task.spawn
      signal
      task.interrupt!
      expect(Timeout.timeout(5) { task.wait.to_h }).to eq(
        id: "call_3",
        name: "brittle",
        value: {cancelled: true, reason: "interrupted"}
      )
    end
  end
end
