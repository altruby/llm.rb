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
    def initialize(mailbox, result, runner_class, id, name, arguments)
      @mailbox = mailbox
      @result = result
      @runner_class = runner_class
      @id = id
      @name = name
      @arguments = arguments
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
          @tool&.send(:interrupt)
        end
      end
    end

    def spawn
      @tool = ::Ractor.new(@mailbox, @runner_class, @id, @name, @arguments) do |mailbox, runner_class, id, name, arguments|
        ##
        # Before the watcher exists, because an interrupt can arrive
        # first: it is a message, and it waits in the inbox until the
        # watcher reads it. The thread the interrupt is raised on is
        # named rather than defaulted, which is what the window asks of
        # a caller: it is `Thread.current`, the ractor's own main
        # thread, and the thread the tool runs on.
        window = LLM::Function::Window.new(thread: ::Thread.current)
        ::Thread.new do
          ::Ractor.receive == :interrupt or next
          ##
          # The window decides whether this is the tool's to handle, or
          # whether the tool has already been and gone.
          window.interrupt!
        rescue ::Ractor::Error
        end
        ##
        # Everything the call needs is prepared outside the window, so
        # the distance from `running!` to the tool's first instruction is
        # the method dispatch and nothing else. The tool is built outside
        # it too: a raise from `initialize` is not an interrupt to
        # answer, and inside the window it would be answered as one.
        kwargs = Hash === arguments ? arguments.transform_keys(&:to_sym) : arguments
        runner = runner_class.new
        window.running!
        result = runner.call(**kwargs)
        ##
        # The window closes the moment the tool has returned and before
        # the result is written, so an interrupt that arrives once the
        # work is done is a no-op rather than a reason to throw the
        # result away.
        window.finished!
        mailbox.send([:done, id, name, result])
      rescue LLM::Interrupt
        mailbox.send([:done, id, name, {cancelled: true, reason: "interrupted"}])
      rescue => ex
        mailbox.send([:done, id, name, {error: true, type: ex.class.name, message: ex.message}])
      end
    end
  end
end
