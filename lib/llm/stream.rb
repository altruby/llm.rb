# frozen_string_literal: true

module LLM
  ##
  # The {LLM::Stream LLM::Stream} class provides the callback interface for
  # streamed model output in llm.rb.
  #
  # A stream object can be an instance of {LLM::Stream LLM::Stream} or a
  # subclass that overrides the callbacks it needs. For basic streaming,
  # llm.rb also accepts any object that implements `#<<`. {#queue} provides
  # a small helper for collecting asynchronous tool work started from a
  # callback.
  #
  # @example Subclass with callbacks
  #   class MyStream < LLM::Stream
  #     def on_content(content)
  #       print content
  #     end
  #
  #     def on_reasoning_content(content)
  #       warn content
  #     end
  #   end
  #
  #   llm = LLM.deepseek(key: ENV["KEY"])
  #   agent = LLM::Agent.new(llm, stream: MyStream.new)
  #   agent.talk "Explain Ruby fibers."
  #
  # @note The `on_*` callbacks run inline with the streaming parser. They
  #   therefore block streaming progress and should generally return as
  #   quickly as possible.
  #
  # The most common callback is {#on_content}, which also maps to `#<<`.
  # Providers may also call {#on_reasoning_content} and {#on_tool_call} when
  # that data is available. Runtime features such as context compaction may
  # also emit lifecycle callbacks like {#on_transform} or {#on_compaction}.
  #
  # @see LLM::Agent Where streams are typically attached
  # @see LLM::Context Where streams are bound per-turn
  class Stream
    require_relative "stream/queue"
    require_relative "stream/io"
    require_relative "stream/disabled"

    ##
    # This method will try to convert its argument into
    # an instance of {LLM::Stream LLM::Stream} or a
    # subclass of it.
    #
    # Acceptable inputs include: {LLM::Stream LLM::Stream}
    # objects, IO objects who implement `#<<`, true, false,
    # and nil. Anything else raises a TypeError.
    #
    # @raise [TypeError]
    # @param [LLM::Stream, #<<, Boolean, NilClass] obj
    # @return [LLM::Stream]
    def self.try(obj, extra: {})
      if LLM::Stream === obj
        obj.tap { _1.extra.merge!(extra) }
      elsif obj.respond_to?(:<<)
        LLM::Stream::IO.new(obj).tap { _1.extra.merge!(extra) }
      elsif obj == true
        LLM::Stream.new.tap { _1.extra.merge!(extra) }
      elsif obj.nil? || obj == false
        LLM::Stream::Disabled.new.tap { _1.extra.merge!(extra) }
      else
        raise TypeError, "invalid stream object"
      end
    end

    ##
    # Returns extra context associated with the current streamed request.
    # @return [Hash]
    def extra
      @extra ||= LLM::Object.from({})
    end

    ##
    # Returns the current context, if one was attached to the stream.
    # @return [LLM::Context, nil]
    def ctx
      extra[:ctx]
    end

    ##
    # Returns a lazily-initialized queue for tool results or spawned work.
    # @return [LLM::Stream::Queue]
    def queue
      @queue ||= Queue.new(self)
    end

    ##
    # Waits for queued tool work to finish and returns function results.
    # Any passed arguments are ignored because queued work is waited according
    # to the actual task types already present in the queue.
    # @return [Array<LLM::Function::Return>]
    def wait(*)
      queue.wait
    end

    ##
    # @return [Boolean]
    def enabled?
      true
    end

    # @group Public callbacks

    ##
    # Called when visible assistant output is streamed.
    # @param [String] content
    #  A chunk of assistant-visible text.
    # @return [nil]
    def on_content(content)
      nil
    end
    alias_method :<<, :on_content

    ##
    # Called when reasoning output is streamed separately from visible content.
    # @param [String] content
    #  A chunk of reasoning text.
    # @return [nil]
    def on_reasoning_content(content)
      nil
    end

    ##
    # Called when a streamed tool call has been fully constructed.
    # A stream implementation may start tool execution here by pushing
    # `@queue << tool.task(:thread).tap(&:spawn)` onto {#queue} — `spawn`
    # returns nil, so `tap` keeps the task while starting it. The task
    # carries the context's guard, so it is checked before the tool runs —
    # a blocked call yields its guard return without executing.
    # @param [LLM::Function] tool
    #  The parsed tool call.
    # @return [nil]
    def on_tool_call(tool)
      nil
    end

    ##
    # Called when queued streamed tool work returns.
    # This callback runs when {#wait} resolves work queued from
    # {#on_tool_call}.
    # @param [LLM::Function] tool
    #  The tool that returned.
    # @param [LLM::Function::Return] result
    #  The completed tool return.
    # @return [nil]
    def on_tool_return(tool, result)
      nil
    end

    ##
    # Called when a request in a turn has completed.
    #
    # This is the boundary between one request and the next: the response
    # is in the context's message history, and a turn that asked for tools
    # runs them after this while a turn that is finished ends here.
    #
    # It is emitted once per successful request, so a request that is
    # retried after a rate limit or a timeout calls this when it lands and
    # not once per attempt. It is also emitted when the stream is disabled:
    # a disabled stream has no output to report, but it is still told that
    # a step ended.
    #
    # @param [LLM::Response] res
    #  The response for the request that completed.
    # @return [nil]
    def on_step(res)
      nil
    end

    ##
    # Called before a context transformer rewrites a prompt.
    # @param [LLM::Transformer] transformer
    # @return [nil]
    def on_transform(transformer)
      nil
    end

    ##
    # Called after a context transformer finishes rewriting a prompt.
    # @param [LLM::Transformer] transformer
    # @return [nil]
    def on_transform_finish(transformer)
      nil
    end

    ##
    # Called before a context compaction starts.
    # @param [LLM::Compactor] compactor
    # @return [nil]
    def on_compaction(compactor)
      nil
    end

    ##
    # Called after a context compaction finishes.
    # @param [LLM::Compactor] compactor
    # @return [nil]
    def on_compaction_finish(compactor)
      nil
    end

    ##
    # Called when a request is retried because it was rate limited or
    # timed out.
    # @param [Exception] error
    #  The error that caused the retry
    # @param [Integer] attempt
    #  The one-based retry attempt number
    # @return [nil]
    def on_retry(error, attempt)
      nil
    end
    alias_method :on_rate_limit, :on_retry

    ##
    # Called before a skill's subagent runs.
    # @param [LLM::Skill] skill
    # @return [nil]
    def on_skill_call(skill)
      nil
    end

    ##
    # Called after a skill's subagent finishes.
    # @param [LLM::Agent] agent
    #  The subagent that ran the skill
    # @param [LLM::Skill] skill
    # @param [LLM::Response, nil] result
    # @return [nil]
    def on_skill_return(agent, skill, result)
      nil
    end

    # @endgroup

    # @group Finders

    ##
    # Resolves a streamed tool call against the current request tools first,
    # then falls back to the global function registry.
    # @param [String] name
    # @return [LLM::Function, nil]
    def __find__(name)
      tools = extra[:tools] || ctx&.params&.dig(:tools) || []
      tool = tools.find do
        candidate = _1.respond_to?(:function) ? _1.function.name : _1.name
        candidate.to_s == name.to_s
      end
      if tool
        tool.respond_to?(:function) ? tool.function : tool
      else
        LLM::Function.find_by_name(name)
      end
    end

    # @endgroup
  end
end
