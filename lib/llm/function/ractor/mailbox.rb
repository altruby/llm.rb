# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Mailbox} class manages the mailbox protocol
  # for a single ractor-backed function call.
  class Ractor::Mailbox
    ##
    # @return [::Ractor]
    attr_reader :task

    ##
    # @param [::Ractor] task
    # @return [LLM::Function::Ractor::Mailbox]
    def initialize(task)
      @task = task
    end

    ##
    # @return [Boolean]
    def alive?
      request(:alive?)
    rescue ::Ractor::ClosedError
      false
    end

    ##
    # @return [Array]
    def wait
      request(:wait)
    end

    ##
    # A cancel for a task whose ractor has gone is a no-op, the same way a
    # cancel for a call that has already returned is one: there is nothing
    # left to interrupt, and the raise belongs to nobody.
    # @return [nil]
    def interrupt!
      task.send([:interrupt])
      nil
    rescue ::Ractor::ClosedError
      nil
    end

    private

    def request(type)
      reply = ::Ractor.new { ::Ractor.receive }
      task.send([type, reply])
      reply.respond_to?(:take) ? reply.take : ::Ractor.select(reply).last
    end
  end
end
