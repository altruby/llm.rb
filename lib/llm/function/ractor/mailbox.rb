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
    # @param [::Ractor] result
    #  The ractor the result is delivered to. It is not `task`: that one
    #  answers `alive?` while the tool runs and goes once the result is
    #  in, while this one holds the result until it is asked for, so a
    #  wait that arrives late is still answered.
    # @return [LLM::Function::Ractor::Mailbox]
    def initialize(task, result)
      @task = task
      @result = result
    end

    ##
    # @return [Boolean]
    def alive?
      request(:alive?)
    rescue ::Ractor::ClosedError
      false
    end

    ##
    # The result, taken from the ractor that holds it rather than asked
    # of the ractor that ran the tool: the second is on its way out by the
    # time a wait arrives late, and a request that races that is refused
    # or accepted and never read.
    # @return [Array]
    def wait
      value_of(@result)
    end

    ##
    # @return [nil]
    def interrupt!
      task.send([:interrupt])
      nil
    end

    private

    ##
    # The value a ractor was given, waited for the way this class waits
    # for anything: `take` where the runtime has it, `Ractor.select`
    # where it does not.
    # @param [::Ractor] ractor
    # @return [Object]
    def value_of(ractor)
      ractor.respond_to?(:take) ? ractor.take : ::Ractor.select(ractor).last
    end

    def request(type)
      reply = ::Ractor.new { ::Ractor.receive }
      task.send([type, reply])
      value_of(reply)
    end
  end
end
