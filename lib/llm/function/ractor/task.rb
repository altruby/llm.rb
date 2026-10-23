# frozen_string_literal: true

class LLM::Function
  ##
  # Wraps a ractor-backed function call.
  #
  # One ractor runs the tool and sends its result to a port
  # after its interrupt watcher has stopped. A thread inside
  # the ractor services interrupts.
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
      @port = Ractor::Port.new
      @exits = Ractor::Port.new
      @ractor = build_task(@port)
      @ractor.monitor(@exits)
      @completion = watch_exit
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
    # Waits on the result port. The completion thread also sends
    # an error to this port if the ractor exits without a result,
    # so a failed ractor cannot leave the caller blocked forever.
    # Later waits answer from memory.
    # @return [LLM::Function::Return]
    def wait
      return @intercepted if intercepted?
      @result ||= begin
        spawn unless @ractor
        ready = @port.receive
        if ready == :__ractor_exited__
          Return.new(@id, @name, {error: true, type: "ractor ended without result"})
        else
          _, id, name, value, @finished_at = ready
          if Hash === value and value[:interrupt] and value[:cookie] == @cookie
            LLM::Interrupt.new
          else
            Return.new(id, name, value)
          end
        end
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
    # @param [Ractor::Port] port
    # @return [Ractor]
    def build_task(port)
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      vars = [port, @runner_class, @id, @name, @arguments, @cookie]
      Ractor.new(*vars) do |*vars|
        LLM::Function::Ractor::Job.new(*vars).call
      end
    end

    ##
    # Watches for ractor termination without waiting for its
    # return value. If the job never sends a result, wake #wait
    # with an error marker. A successful result is sent first.
    # @return [Thread]
    def watch_exit
      exits = @exits
      port = @port
      ::Thread.new do
        begin
          exits.receive
        rescue ::Ractor::Error
          # A closed monitor port still means the task has ended.
        ensure
          @exited = true
          port.send(:__ractor_exited__)
        end
      end
    end
  end
end
