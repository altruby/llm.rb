# frozen_string_literal: true

class LLM::Function
  ##
  # Runs a tool call inside the one ractor a task spawns,
  # sending its result to the task's port.
  class Ractor::Job
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @param [Ractor::Port] port
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @param [String] cookie
    # @return [LLM::Function::Ractor::Job]
    def initialize(port, runner_class, id, name, arguments, cookie)
      @port = port
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
      @cookie = cookie
    end

    ##
    # @return [void]
    def call
      LLM.debug "[ractor #{@cookie}] job started"
      finished_at = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      window = LLM::Function::Window.new(thread: ::Thread.current)
      runner = @runner_class.new
      watcher = watch(runner, window)
      kwargs = Hash === @arguments ? @arguments.transform_keys(&:to_sym) : @arguments
      window.running!
      result = runner.call(**kwargs)
      LLM.debug "[ractor #{@cookie}] tool returned"
      window.finished!
      [:done, @id, @name, result, finished_at.()]
    rescue LLM::Interrupt
      LLM.debug "[ractor #{@cookie}] tool interrupted"
      send_result([:done, @id, @name, {interrupt: true, cookie: @cookie}, finished_at.()], watcher)
      watcher = nil
    rescue => ex
      LLM.debug "[ractor #{@cookie}] tool error #{ex.class}"
      send_result([:done, @id, @name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()], watcher)
      watcher = nil
    ensure
      LLM.debug "[ractor #{@cookie}] stopping interrupt watcher"
      watch_stop(watcher)
      LLM.debug "[ractor #{@cookie}] job ensure complete"
    end

    private

    def send_result(result, watcher)
      watch_stop(watcher)
      @port.send(result)
    end

    ##
    # Stop the interrupt watcher before returning from the ractor body.
    # Killing a thread is asynchronous: join it before sending the
    # result to ensure the job has no outstanding interrupt handler.
    # The watcher may be blocked in Ractor.receive, so do not rely on a
    # :stop message being delivered to shut it down.
    # @param [Thread, nil] watcher
    # @return [void]
    def watch_stop(watcher)
      watcher&.kill&.join
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
