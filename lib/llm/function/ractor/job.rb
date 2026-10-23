# frozen_string_literal: true

class LLM::Function
  ##
  # Runs a tool call inside the one ractor a task spawns;
  # sends its result to the task's port after the tool finishes,
  # before waiting for the interrupt watcher to stop.
  class Ractor::Job
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @param [Ractor::Port] resultp
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @param [String] cookie
    # @return [LLM::Function::Ractor::Job]
    def initialize(resultp, runner_class, id, name, arguments, cookie)
      @resultp = resultp
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
      resultm = [:done, @id, @name, result, finished_at.()]
    rescue LLM::Interrupt
      LLM.debug "[ractor #{@cookie}] tool interrupted"
      resultm = [:done, @id, @name, {interrupt: true, cookie: @cookie}, finished_at.()]
    rescue => ex
      LLM.debug "[ractor #{@cookie}] tool error #{ex.class}"
      resultm = [:done, @id, @name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()]
    ensure
      window&.finished!
      LLM.debug "[ractor #{@cookie}] stopping interrupt watcher"
      watcher&.kill
      ##
      # On Windows, joining a killed thread blocked
      # in Ractor.receive can stall the job indefinitely.
      # Publish the result before joining it.
      @resultp.send(resultm) if resultm
      watch_stop(watcher)
      LLM.debug "[ractor #{@cookie}] job ensure complete"
    end

    private

    ##
    # Join the interrupt watcher after publishing the result, so a
    # stalled join cannot block the caller waiting for the tool.
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
