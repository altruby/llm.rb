# frozen_string_literal: true

require "setup"

##
# Where a wait's answer comes from.
#
# A ractor answers one round trip and goes with the answering of it, so
# `Mailbox#wait` is not a request a terminated ractor can be asked. The
# task's own ractor is not asked for the result at all: the job hands the
# result to a ractor of the task's own before that ractor ends, and the
# wait takes it from there, whether it arrives before or after the task's
# ractor has gone. A wait after the first is answered from memory, the way
# `LLM::Function::Thread::Task#wait` answers from the thread's value.
#
# **Every wait has a deadline.** A raise cannot be relied on to interrupt
# a wait on a ractor, so each of them runs on a thread of its own and is
# joined with a timeout: a round trip that does not come back is what
# this is about, and an example for it has to fail rather than hang.
RSpec.describe LLM::Function::Ractor::Task do
  ##
  # The ractor's examples are not supported by yajl or oj, and the matrix
  # spells the cell that supports them `JSON`, so the parser is compared
  # as it is written.
  before do
    skip "not supported by yajl or oj" unless ENV.fetch("JSON_PARSER", "json").downcase == "json"
  end

  ##
  # Runs the block on a thread of its own and joins it, so a wait that
  # never comes back is a failure that names the wait rather than a hang.
  def within(seconds = 5, &block)
    thread = Thread.new(&block)
    thread.join(seconds) ? thread.value : raise("timed out after #{seconds} seconds")
  end

  ##
  # A tool that returns at once, so that the task has a result and then a
  # reason to go.
  let(:task) do
    Class.new(LLM::Tool) do
      name "quick"

      def call
        {ok: true}
      end
    end.function.dup.tap do |fn|
      fn.id = "call_1"
      fn.arguments = {}
    end.task(:ractor)
  end

  describe "a task that has been waited on" do
    it "answers a second wait from the result it has" do
      first = within { task.wait }
      expect(within { task.wait }).to equal(first)
    end

    it "answers a second wait with what the first one had" do
      first = within { task.wait }
      expect(within { task.wait }.to_h).to eq(first.to_h)
    end

    it "answers alive? from the result it has" do
      within { task.wait }
      expect(within { task.alive? }).to be(false)
    end
  end

  describe "a wait that arrives after the result is in" do
    it "is answered by the ractor the result was delivered to" do
      task.spawn
      ##
      # The tool is quick and the wait is late: by the time it comes, the
      # task's own ractor has answered the round trip it was there for
      # and gone with it. Before this change the wait went to that ractor,
      # and what it left behind was a hanging job rather than a failure.
      sleep 0.05
      expect(within { task.wait }.to_h).to eq(
        id: "call_1", name: "quick", value: {ok: true}
      )
    end
  end
end
