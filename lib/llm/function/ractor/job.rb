# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class manages execution and mailbox
  # coordination for a single ractor-backed function call.
  class Ractor::Job
    ##
    # @param [::Ractor] mailbox
    # @param [::Ractor] result
    #  The ractor the result is handed to, which the task holds it in.
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @return [LLM::Function::Ractor::Job]
    def initialize(mailbox, result, runner_class, id, name, arguments, cookie)
      @mailbox = mailbox
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

    def spawn
      @tool = ::Ractor.new(@mailbox, @runner_class, @id, @name, @arguments, @cookie) do |mailbox, runner_class, id, name, arguments, cookie|
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
        mailbox.send([:done, id, name, result, finished_at.()])
      rescue LLM::Interrupt
        mailbox.send([:done, id, name, {interrupt: true, cookie:}, finished_at.()])
      rescue => ex
        mailbox.send([:done, id, name, {error: true, type: ex.class.name, message: ex.message}, finished_at.()])
      end
    end
  end
end
