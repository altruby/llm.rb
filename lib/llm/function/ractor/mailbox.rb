# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Mailbox} class
  # manages the mailbox protocol for a single
  # ractor-backed function call.
  class Ractor::Mailbox
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @return [Ractor]
    attr_reader :supervisor

    ##
    # @param [Ractor] supervisor
    # @param [Ractor] result
    # @return [LLM::Function::Ractor::Mailbox]
    def initialize(supervisor, result)
      @supervisor = supervisor
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
      @result.value
    end

    ##
    # Delivers an interrupt to the Ractor that
    # supervises the second ractor that is running
    # a tool. The supervisor delivers the interrupt
    # to the tool ractor.
    # @return [nil]
    def interrupt!
      supervisor.send([:interrupt])
      nil
    rescue ::Ractor::ClosedError
      nil
    end

    private

    ##
    # @param [Symbol] type
    # @return [Object]
    def request(type)
      reply = Ractor.new { Ractor.receive }
      supervisor.send([type, reply])
      reply.value
    end
  end
end
