# frozen_string_literal: true

class LLM::Function
  ##
  # Runs a tool call inside the one ractor a task spawns,
  # returning its result to the task via Ractor#value.
  class Ractor::Job
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @param [String] cookie
    # @return [LLM::Function::Ractor::Job]
    def initialize(runner_class, id, name, arguments, cookie)
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
      @cookie = cookie
    end

    ##
    # @return [void]
    def call
      finished_at = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      window = LLM::Function::Window.new(thread: ::Thread.current)
      runner = @runner_class.new
      watcher = watch(runner, window)
      kwargs = Hash === @arguments ? @arguments.transform_keys(&:to_sym) : @arguments
      window.running!
      result = runner.call(**kwargs)
      window.finished!
      [:done, @id, @name, result, finished_at.()]
    rescue LLM::Interrupt
      [:done, @id, @name, {interrupt: true, cookie: @cookie}, finished_at.()]
    rescue => ex
      [:done, @id, @name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()]
    ensure
      watch_stop(watcher)
    end

    private

    ##
    # Stop the interrupt watcher when the call ends. Do not wait for
    # Ractor.receive to wake up: on some platforms that thread can remain
    # blocked even after a :stop is sent, preventing Ractor#value from
    # returning despite the tool having finished.
    # @param [Thread, nil] watcher
    # @return [void]
    def watch_stop(watcher)
      if watcher
        ::Ractor.current.send(:stop)
        watcher.kill
      end
      nil
    rescue ::Ractor::Error
      nil
    end

    ##
    # Watches for an interrupt on a thread of the ractor's own, so the main
    # thread can stay inside the tool.
    # @param [LLM::Tool] runner
    # @param [LLM::Function::Window] window
    # @return [Thread]
    def watch(runner, window)
      ::Thread.new do
        loop do
          kind = begin
            ::Ractor.receive
          rescue ::Ractor::Error
            break
          end
          break if kind == :stop
          next unless kind == :interrupt
          begin
            LLM::Function.interrupt(runner)
          ensure
            window.interrupt!
          end
        end
      end
    end
  end
end
