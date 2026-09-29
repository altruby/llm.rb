# frozen_string_literal: true

module LLM::Function::Sequential
  ##
  # Wraps an array of {LLM::Function::Sequential::Task} objects
  # for sequential execution. Provides the same interface as
  # concurrent group wrappers so callers can flow through
  # `task(strategy).wait` regardless of the strategy being
  # used.
  class Group < LLM::Function::Group
    ##
    # @param [Array<LLM::Function::Sequential::Task>] tasks
    #  One or more Sequential::Task objects
    # @return [LLM::Function::Sequential::Group]
    def initialize(tasks)
      @tasks = tasks
      @owner = nil
    end

    ##
    # @return [nil]
    def spawn
      # no-op (execution happens in wait)
      @tasks.each(&:spawn)
      nil
    ensure
      @spawned = true
    end

    ##
    # @return [Boolean]
    def alive?
      @tasks.any?(&:alive?)
    end

    ##
    # Interrupts the thread blocked in {#wait}, and tells the tasks.
    #
    # Sequential functions run on the caller's thread, so the raise is what
    # interrupts the call and it has to land there. The tasks are told as
    # well, which is what every other group does and what this one skipped -
    # and telling them first means a tool that releases a resource has done
    # so by the time the raise lands on it.
    # @return [nil]
    def interrupt!
      @tasks.each(&:interrupt!)
      @owner&.raise(LLM::Interrupt)
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # @return [Array<LLM::Function::Return>]
    def wait
      @owner = Thread.current
      @tasks.map(&:wait)
    ensure
      @owner = nil
    end
    alias_method :value, :wait
  end
end
