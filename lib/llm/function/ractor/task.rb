# frozen_string_literal: true

class LLM::Function
  ##
  # The {LLM::Function::Ractor::Task} class wraps a ractor-backed function
  # call and delegates mailbox coordination to
  # {LLM::Function::Ractor::Mailbox}.
  class Ractor::Task < LLM::Function::Task
    ##
    # @return [LLM::Function::Ractor::Mailbox]
    attr_reader :mailbox

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
      @tracer = options.fetch(:tracer, nil)
    end

    ##
    # @return [LLM::Function::Ractor::Task]
    def spawn
      return if @guarded
      @span = @tracer&.on_tool_start(
        id: @id, name: @name,
        arguments: @arguments, model: @model
      )
      @mailbox = Ractor::Mailbox.new(build_task)
      self
    end

    ##
    # A task that has been waited on is not alive, and it answers that
    # from the result it holds rather than by asking a ractor that has
    # gone with the answering of the wait.
    # @return [Boolean]
    def alive?
      return false if @result
      @mailbox&.alive? || false
    end

    ##
    # @return [nil]
    def interrupt!
      mailbox&.interrupt!
      nil
    end
    alias_method :cancel!, :interrupt!

    ##
    # The result, once there is one, is answered from memory, the way
    # {LLM::Function::Thread::Task#wait} answers from the thread's value.
    # A ractor answers one round trip and goes with the answering of it,
    # so a second trip is not one it can be asked for: the ractor is on
    # its way out, and a request that races that is either refused or
    # accepted and never read.
    # @return [LLM::Function::Return]
    def wait
      return @guarded if @guarded
      @result ||= begin
        spawn unless @mailbox
        id, name, value = mailbox.wait
        result = Return.new(id, name, value)
        @tracer&.on_tool_finish(result:, span: @span)
        result
      end
    end
    alias_method :value, :wait

    ##
    # @return [Class]
    def group_class
      LLM::Function::Ractor::Group
    end

    private

    def build_task
      ::Ractor.new(@runner_class, @id, @name, @arguments) do |runner_class, id, name, arguments|
        LLM::Function::Ractor::Job.new(::Ractor.current, runner_class, id, name, arguments).call
      end
    end
  end
end
