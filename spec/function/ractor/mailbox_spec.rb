# frozen_string_literal: true

require "setup"

##
# The cancel contract for a ractor that has gone.
#
# `LLM::Function::Return#interrupt!` is a no-op for a call that has
# already returned, and this is the same reading one step further on:
# there is no ractor left to answer, so an interrupt is a no-op rather
# than a raise. `Ractor#send` raises `Ractor::ClosedError` once a ractor
# has terminated, and both places a cancel passes through absorb it - the
# mailbox, because the caller asked for a no-op, and the job's own loop,
# because the ractor that would raise is the one that answers whoever is
# waiting on it.
#
# The mailbox's own example is written against a ractor of its own rather
# than a task, so that "the ractor has gone" is something it waits for
# rather than sleeps at: `take` where the runtime has it, and
# `Ractor.select` where it does not, is the pair the mailbox itself uses
# for the same reason.
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

  describe "an interrupt for a tool that has gone" do
    ##
    # The ractor's interrupt path is not supported by yajl or oj, and the
    # matrix spells the cell that supports it `JSON`, so the parser is
    # compared as it is written.
    before do
      skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
    end

    ##
    # The tool holds, so that the wait below is registered before the
    # result is, which is what keeps the task's ractor alive to take the
    # cancel that follows.
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
      task.wait
      ##
      # The tool has returned, so its ractor has gone. The task's ractor is
      # still there, because the wait above is one it has to answer, and
      # the cancel is for the tool that is not there any more.
      task.interrupt!
    end

    it "leaves the task able to answer a wait" do
      expect(task.wait.to_h).to eq(id: "call_1", name: "holding", value: {ok: true})
    end
  end
end
