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
      ##
      # The result is delivered to a ractor of this task's own rather
      # than through its mailbox. The mailbox ractor answers `alive?`
      # while the tool runs and goes once the result is in, so a wait
      # that arrives after it has gone has nobody to answer it. This one
      # receives the result once and holds it until it is asked.
      result = ::Ractor.new { ::Ractor.receive }
      @mailbox = Ractor::Mailbox.new(build_task(result), result)
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
    # The first wait is answered by the ractor the result was delivered
    # to, which has it whether or not the task's own ractor is still
    # there. Every wait after that is answered from memory, the way
    # {LLM::Function::Thread::Task#wait} answers from the thread's value.
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

    def build_task(result)
      ::Ractor.new(result, @runner_class, @id, @name, @arguments) do |result, runner_class, id, name, arguments|
        LLM::Function::Ractor::Job.new(::Ractor.current, result, runner_class, id, name, arguments).call
      end
    end
  end
end
