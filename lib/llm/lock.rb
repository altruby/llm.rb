# frozen_string_literal: true

module LLM
  module Lock
    ##
    # Provides a thread-safe lock
    # @param [Symbol] name The name of the lock
    # @param [Proc] block The block to execute within the lock
    # @return [void]
    def self.lock(name, &block)
      if Ractor.main?
        @monitors[name].synchronize(&block)
      else
        nil
      end
    end

    ##
    # @api private
    def self.set_monitors
      @monitors = {debug: Monitor.new,
                   require: Monitor.new,
                   inherited: Monitor.new,
                   registry: Monitor.new,
                   mcp: Monitor.new}

    end
    set_monitors
    private_class_method :set_monitors
  end
end
