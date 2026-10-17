# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class has a reference
  # to two ractors: a supervisor, and another Ractor that
  # runs the tool call.
  class Ractor::Job
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @param [Ractor] supervisor
    # @param [Ractor] result
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @return [LLM::Function::Ractor::Job]
    def initialize(supervisor, result, runner_class, id, name, arguments, cookie)
      @supervisor = supervisor
      @result = result
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
      @cookie = cookie
    end

    ##
    # @return [void]
    def call
      spawn
      wait
    end

    private

    ##
    # The loop owes one thing: the result, handed to the ractor the task
    # holds it in before this one ends. It answers `alive?` while the tool
    # runs, forwards interrupts to the tool, hands the result over, and
    # goes - so a wait cannot arrive at a ractor that is on its way out,
    # which is what asking this one for a result used to do.
    # @return [void]
    def wait
      loop do
        case ::Ractor.receive
        in [:done, *data]
          @result.send(data)
          break
        in [:alive?, reply]
          reply.send(true)
        in [:interrupt]
          interrupt_tool
        end
      end
    end

    ##
    # Forwards an interrupt to the tool's ractor.
    #
    # A tool whose ractor has gone has nothing left to interrupt, and this
    # loop is the thing that owes the result to the ractor the task waits
    # on. A raise here takes the loop with it before the result has been
    # handed over, so that a forward to a ractor that has gone turns the
    # failure that used to name it into a wait that never comes back.
    # @return [nil]
    def interrupt_tool
      @tool&.send(:interrupt)
      nil
    rescue ::Ractor::ClosedError
      nil
    end

    ##
    # @return [void]
    def spawn
      vars  = [@supervisor, @runner_class, @id, @name, @arguments, @cookie]
      @tool = Ractor.new(*vars) do |supervisor, runner_class, id, name, arguments, cookie|
        finished_at = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        window = LLM::Function::Window.new(thread: ::Thread.current)
        runner = runner_class.new
        ::Thread.new do
          kind = begin
            ::Ractor.receive
          rescue ::Ractor::Error
            next
          end
          next unless kind == :interrupt
          begin
            LLM::Function.interrupt(runner)
          ensure
            window.interrupt!
          end
        end
        kwargs = Hash === arguments ? arguments.transform_keys(&:to_sym) : arguments
        window.running!
        result = runner.call(**kwargs)
        window.finished!
        supervisor.send([:done, id, name, result, finished_at.()])
      rescue LLM::Interrupt
        supervisor.send([:done, id, name, {interrupt: true, cookie:}, finished_at.()])
      rescue => ex
        supervisor.send([:done, id, name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()])
      end
    end
  end
end
