# frozen_string_literal: true

class LLM::Function
  ##
  # Wraps a ractor-backed function call.
  #
  # One ractor runs the tool and returns its result through
  # {Ractor#value}. A thread inside the ractor services
  # interrupts.
  class Ractor::Task < LLM::Function::Task
    ##
    # @api private
    Ractor = ::Ractor
    private_constant :Ractor

    ##
    # @return [LLM::Tracer, nil]
    attr_reader :tracer

    ##
    # @return [String]
    attr_reader :cookie

    ##
    # @return [Object]
    attr_reader :span

    ##
    # @param [LLM::Function] fn
    # @param [Hash] options
    # @option options [LLM::Tracer, nil] :tracer
    # @option options [Class] :runner_class
    # @option options [String, nil] :id
    # @option options [String] :name
    # @option options [Hash, Array, nil] :arguments
    # @option options [String, nil] :model
    # @return [LLM::Function::Ractor::Task]
    def initialize(fn, options = {})
      super
      @runner_class = options.fetch(:runner_class)
      @id = options.fetch(:id)
      @name = options.fetch(:name)
      @arguments = options.fetch(:arguments)
      @model = options.fetch(:model, nil)
      @cancelled = false
      @cookie = SecureRandom.hex
    end

    ##
    # @return [LLM::Function::Ractor::Task]
    def spawn
      @span = @tracer&.on_tool_start(
        id: @id, name: @name,
        arguments: @arguments, model: @model
      )
      return if intercepted?
      @ractor = build_task
      @exits = Ractor::Port.new
      @ractor.monitor(@exits)
      watch_exit
      if @cancelled
        @cancelled = false
        interrupt!
      end
      self
    end

    ##
    # @return [Boolean]
    def alive?
      return false if @result
      @ractor ? !@exited : false
    end

    ##
    # Tells the tool to stop.
    #
    # A cancel that arrives before `spawn` is remembered and
    # delivered by it.
    # @return [nil]
    def interrupt!
      if @ractor
        @ractor.send(:interrupt)
      else
        @cancelled = true
      end
      nil
    rescue ::Ractor::ClosedError
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # Waits for the ractor's return value. Unlike receiving
    # on a port, this also finishes if the ractor dies before
    # producing a result. Later waits answer from memory.
    # @return [LLM::Function::Return]
    def wait
      return @intercepted if intercepted?
      @result ||= begin
        spawn unless @ractor
        _, id, name, value, @finished_at = @ractor.value
        if Hash === value and value[:interrupt] and value[:cookie] == @cookie
          LLM::Interrupt.new
        else
          Return.new(id, name, value)
        end
      rescue ::Ractor::RemoteError
        Return.new(@id, @name, {error: true, type: "ractor ended without result"})
      end
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Ractor::Group
    end

    private

    ##
    # @return [Ractor]
    def build_task
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      vars = [@runner_class, @id, @name, @arguments, @cookie]
      Ractor.new(*vars) do |*vars|
        LLM::Function::Ractor::Job.new(*vars).call
      end
    end

    ##
    # Observes termination independently of {#wait}, so
    # {#alive?} works even when nobody waits for the result.
    # Use the monitor port rather than joining the same ractor
    # concurrently with {#wait}'s `value` call.
    # @return [Thread]
    def watch_exit
      ::Thread.new do
        begin
          @exits.receive
        rescue ::Ractor::RemoteError
          # A failed ractor is no longer alive either.
        ensure
          @exited = true
        end
      end
    end
  end
end
