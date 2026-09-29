# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Job} class manages execution and mailbox
  # coordination for a single ractor-backed function call.
  class Ractor::Job
    ##
    # @param [::Ractor] mailbox
    # @param [Class] runner_class
    # @param [String, nil] id
    # @param [String] name
    # @param [Hash, Array, nil] arguments
    # @return [LLM::Function::Ractor::Job]
    def initialize(mailbox, runner_class, id, name, arguments)
      @mailbox = mailbox
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

    def wait
      done = false
      result = nil
      waiters = []
      loop do
        case ::Ractor.receive
        in [:done, *data]
          result ||= data
          done = true
          waiters.each { _1.send(result) }
          break unless waiters.empty?
          waiters.clear
        in [:alive?, reply]
          reply.send(!done)
        in [:wait, reply]
          if done
            reply.send(result)
            break
          else
            waiters << reply
          end
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
        # watcher reads it. The window names the thread the tool runs on,
        # so it does not depend on what `Thread.main` means in a ractor.
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
        # the method dispatch and nothing else.
        kwargs = Hash === arguments ? arguments.transform_keys(&:to_sym) : arguments
        window.running!
        result = runner_class.new.call(**kwargs)
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
