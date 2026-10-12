# frozen_string_literal: true

class LLM::Function
  ##
  # Abstract superclass for all concurrency strategy groups.
  # Each strategy (sequential, thread, fiber, async, fork, ractor)
  # subclasses this and implements {#alive?}, {#interrupt!}, and
  # {#wait}.
  class Group
    ##
    # @abstract
    # @return [nil]
    def spawn
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [Boolean]
    def alive?
      raise NotImplementedError
    end

    ##
    # @abstract
    # @return [nil]
    def interrupt!
      raise NotImplementedError
    end
    alias_method :cancel!, :interrupt!

    ##
    # @abstract
    # @return [Array<LLM::Function::Return>]
    def wait
      raise NotImplementedError
    end
    alias_method :value, :wait
  end
end
