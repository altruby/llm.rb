# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Mailbox} class
  # manages the mailbox protocol for a single
  # ractor-backed function call.
  class Ractor::Mailbox
    ##
    # @return [Ractor]
    attr_reader :task

    ##
    # @param [Ractor] task
    # @param [Ractor] result
    # @return [LLM::Function::Ractor::Mailbox]
    def initialize(task, result)
      @task = task
      @result = result
    end

    ##
    # Whether the task is still running.
    # @return [Boolean]
    def alive?
      request(:alive?)
    rescue ::Ractor::ClosedError
      false
    end

    ##
    # Returns whatever the tool ractor wrote
    # to its mailbix.
    #
    # It taken from the ractor that holds the
    # result instead of the ractor that ran
    # the tool: the second is on its way out
    # by the time a wait arrives late, and a
    # request that races that is refused or
    # accepted and never read.
    # @return [Array]
    def wait
      take(@result)
    end

    ##
    # Delivers an interrupt to the Ractor that
    # supervises the second ractor that is running
    # a tool. The supervisor delivers the interrupt
    # to the tool ractor.
    # @return [nil]
    def interrupt!
      task.send([:interrupt])
      nil
    rescue ::Ractor::ClosedError
      nil
    end

    private

    ##
    # @param [Ractor] ractor
    # @return [Object]
    def take(ractor)
      ractor.respond_to?(:take) ? ractor.take : ::Ractor.select(ractor).last
    end

    ##
    # @param [Symbol] type
    # @return [Object]
    def request(type)
      reply = ::Ractor.new { ::Ractor.receive }
      task.send([type, reply])
      take(reply)
    end
  end
end
