# frozen_string_literal: true

module LLM
  module Lock
    ##
    # @api private
    @monitors = {
      debug: Monitor.new,
      require: Monitor.new,
      inherited: Monitor.new,
      registry: Monitor.new,
      mcp: Monitor.new
    }

    ##
    # Provides a thread-safe lock
    # @param [Symbol] name The name of the lock
    # @param [Proc] block The block to execute within the lock
    # @return [void]
    def self.synchronize(name, &block)
      if Ractor.main?
        @monitors[name].synchronize(&block)
      else
        nil
      end
    end
  end
end
