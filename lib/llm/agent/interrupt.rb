# frozen_string_literal: true

class LLM::Agent
  ##
  # Stop an agent in its tracks.
  #
  # The {LLM::Agent::Interrupt} module extends
  # the instance variable `@caller` (an instance
  # of {LLM::Object}) that belongs to an agent
  # and its context.
  #
  # The `@caller` instance variable captures the
  # agent's thread, fiber, and scheduler. The
  # variable is in scope for as long as an agent
  # is running and it provides other threads and
  # fibers with access to the agent's thread,
  # fiber and scheduler.
  #
  # A different thread or fiber can use this module
  # and the object it extends (`@caller`) to stop
  # an agent in its tracks via the raise of
  # {LLM::Interrupt LLM::Interrupt} on the
  # agent's thread, or fiber.
  #
  # @note
  #  The method provided by this module is
  #  not called directly, and the `@caller`
  #  instance variable is private. The
  #  {LLM::Agent#interrupt!} and {LLM::Context#interrupt!}
  #  methods call it on your behalf.
  #
  # @see LLM::Agent#run_loop
  # @see LLM::Context#interrupt!
  module Interrupt
    ##
    # Ends the turn where it is.
    #
    # Which name receives the raise is decided by who is cancelling:
    #
    #   another thread  the thread, because a fiber belongs to the thread
    #                   that made it and cannot be entered from another
    #                   one. The raise lands in whichever fiber that
    #                   thread is running, which is the turn's, because
    #                   the turn is what it is doing.
    #
    #   the same thread the fiber, because raising on the thread would
    #                   raise in the canceller that asked for it.
    #
    # A fiber scheduler is the case the second rule is for: a turn under
    # Falcon or Async runs on a fiber of the reactor's thread, and a cancel
    # that arrives on that thread is another fiber asking. Such a fiber is
    # asked for through the scheduler, the way
    # {LLM::Function::Fiber::Task#interrupt!} asks, because a direct raise
    # into a scheduled fiber does not transfer: it suspends the thread that
    # raises, and that thread is the canceller's. A fiber with no scheduler
    # behind it - a turn an application ran in a fiber of its own - is raised
    # into directly, which is what such a fiber is for.
    #
    # Nothing is announced to the tracer here, and that is the point: this
    # delivers the raise and nothing else, so the callback belongs to the
    # frame that catches it rather than to the canceller's thread.
    # {LLM::Agent#run_loop} catches a turn's and announces `scope: :agent`,
    # and {LLM::Context#wait} announces `scope: :tool` from its own rescue
    # the same way, before the caller is given the interrupt either of them
    # ended.
    #
    # Nothing is raised when the record holds no fiber, and nothing is raised
    # when the turn ended between the read and the raise, which is the
    # ordinary race, because a cancel that arrives after a turn is not a
    # failure.
    # @return [nil]
    def interrupt!
      if thread.equal?(Thread.current)
        if fiber
          if scheduler
            scheduler.fiber_interrupt(fiber, LLM::Interrupt.new("agent interrupted"))
          else
            fiber.raise(LLM::Interrupt, "agent interrupted")
          end
        end
      else
        thread.raise(LLM::Interrupt, "agent interrupted")
      end
      nil
    rescue ThreadError, FiberError
      nil
    end
  end
end
