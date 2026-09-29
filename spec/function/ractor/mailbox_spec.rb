# frozen_string_literal: true

require "setup"

##
# The cancel contract for a ractor that has gone.
#
# `LLM::Function::Return#interrupt!` is a no-op for a call that has
# already returned, and this is the same reading one step further on:
# there is no ractor left to answer, so an interrupt is a no-op rather
# than a raise. `Ractor#send` raises `Ractor::ClosedError` once a ractor
# has terminated, which is what a cancel finds when it arrives late.
#
# **The example waits, it does not sleep.** The ractor it cancels against
# is one it made itself, and it is waited on by taking its value, which
# blocks until the ractor has terminated - the pair the mailbox itself
# uses, `take` where the runtime has it and `Ractor.select` where it does
# not. That wait ends, because the ractor is on its way out rather than
# being asked for something it might never send.
#
# A task is not used here. The first version of this file waited on one,
# and a Ruby 3.4 job hung on that wait: a task answers one wait and goes
# with the answering of it, which the run before that one showed as
# `Ractor::ClosedError` on the wait after it. `Mailbox#interrupt!` is what
# is under test, and a ractor of the example's own reaches it with a wait
# that ends.
RSpec.describe LLM::Function::Ractor::Mailbox do
  let(:ractor) { ::Ractor.new { :done } }
  let(:mailbox) { LLM::Function::Ractor::Mailbox.new(ractor) }

  before do
    ##
    # Takes the value, which blocks until the ractor has terminated.
    ractor.respond_to?(:take) ? ractor.take : ::Ractor.select(ractor).last
  end

  it "answers an interrupt for a ractor that has gone with nil" do
    expect(mailbox.interrupt!).to be_nil
  end
end
