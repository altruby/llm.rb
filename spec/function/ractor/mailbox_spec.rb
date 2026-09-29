# frozen_string_literal: true

require "setup"

##
# The cancel contract for a ractor that has gone.
#
# `LLM::Function::Return#interrupt!` is a no-op for a call that has
# already returned, and this is the same reading one step further on:
# there is no ractor left to answer, so an interrupt is a no-op rather
# than a raise. `Ractor#send` raises `Ractor::ClosedError` once a ractor
# has terminated, and a terminated ractor is what a cancel finds - the
# task's own ractor goes once it has answered the wait for its result,
# and the tool's ractor goes with the tool.
#
# **The examples wait, they do not sleep.** A ractor of the example's own
# is waited on by taking its value, which blocks until it has terminated.
# A task is waited on through its own API, and the cancel that follows is
# the one that used to raise.
RSpec.describe LLM::Function::Ractor::Mailbox do
  describe "an interrupt for a ractor that has gone" do
    let(:ractor) { ::Ractor.new { :done } }
    let(:mailbox) { LLM::Function::Ractor::Mailbox.new(ractor) }

    before do
      ##
      # Takes the value, which blocks until the ractor has terminated.
      ractor.respond_to?(:take) ? ractor.take : ::Ractor.select(ractor).last
    end

    it "is a no-op rather than a raise" do
      expect(mailbox.interrupt!).to be_nil
    end
  end

  describe "an interrupt for a task that has returned" do
    ##
    # The ractor's interrupt path is not supported by yajl or oj, and the
    # matrix spells the cell that supports it `JSON`, so the parser is
    # compared as it is written.
    before do
      skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
    end

    ##
    # The tool holds, so that the wait below is registered before the
    # result is, and the task's ractor has a wait to answer rather than
    # leaving before it can answer one.
    let(:task) do
      Class.new(LLM::Tool) do
        name "holding"

        def call
          sleep 0.2
          {ok: true}
        end
      end.function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {}
      end.task(:ractor)
    end

    before do
      task.spawn
      ##
      # The wait returns, and the task's ractor goes with the answering of
      # it. The cancel is for a task that is no longer there.
      task.wait
    end

    it "is a no-op rather than a raise" do
      expect(task.interrupt!).to be_nil
    end
  end
end
