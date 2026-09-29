# frozen_string_literal: true

class LLM::Function
  ##
  # The stretch of a call that an interrupt belongs to.
  #
  # A raise cannot be aimed at a region of code, only permitted for one -
  # it lands wherever the thread it targets happens to be. This is what
  # permits it: an interrupt that arrives while the tool is running is
  # raised on the tool at once, and one that arrives before the tool runs
  # is held until it does, where the tool's own `rescue` can have it.
  #
  # Held rather than answered, because arriving early is not the same as
  # being declined: the tool has not had its chance yet. And afterwards
  # there is nothing to interrupt - a cancel that arrives once the work is
  # finished is a no-op, which is what
  # {LLM::Function::Return#interrupt!} already says one is.
  class Window
    ##
    # @param [Thread] thread
    #  The thread the interrupt is raised on, which is the one running the
    #  tool. An argument rather than `::Thread.main` so that a strategy
    #  whose tool runs elsewhere, and a spec, can say which thread they
    #  mean.
    # @return [LLM::Function::Window]
    def initialize(thread: ::Thread.main)
      @thread = thread
      @mutex = Mutex.new
      @state = :idle
    end

    ##
    # Called from the thread that raises - the watcher - and not from the
    # tool's.
    #
    # It waits while the window has not opened, and returns without
    # raising once it has closed. In between, the raise it issues lands on
    # the tool.
    #
    # The wait is a poll, and it is a poll because this class is used
    # inside a ractor too. With a condition variable there the waiter is
    # never woken on Ruby 3.3: the interrupt this exists for arrives while
    # the window is idle, and it waits out its timeout being raised for a
    # window that has opened beside it. `sleep` is the one wait a ractor
    # is known to keep, and every ractor tool in this project's examples
    # already relies on it.
    # @return [void]
    def interrupt!
      sleep(0.001) while idle?
      return unless running?
      @thread.raise(LLM::Interrupt)
    end

    ##
    # Called from the tool's thread, immediately before the call.
    #
    # It does not wait for the watcher: it changes the state and returns,
    # so the thread that is about to call the tool stays ahead of the
    # thread that is about to interrupt it. By the time the watcher is
    # scheduled, the tool is running.
    # @return [void]
    def running!
      @mutex.synchronize { @state = :running }
    end

    ##
    # Called from the tool's thread, once it has returned - in the happy
    # path before the result is written, and in `ensure` for every other.
    # A waiter holding an interrupt then finds there is nothing to
    # interrupt.
    # @return [void]
    def finished!
      @mutex.synchronize { @state = :finished }
    end

    private

    def idle?
      @mutex.synchronize { @state == :idle }
    end

    def running?
      @mutex.synchronize { @state == :running }
    end
  end
end
