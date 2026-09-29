# frozen_string_literal: true

module LLM
  ##
  # Writes the conversation down when a request completes.
  #
  # {LLM::Step LLM::Step} is an {LLM::Stream LLM::Stream} extension. A stream
  # that is extended with it saves the conversation after every request, so a
  # turn that is interrupted - by a crash, by a deploy, or by a provider that
  # refuses - can be continued rather than started over.
  #
  # It saves through the record the context is bound to ({LLM::Context#record}),
  # and it knows both the ORMs llm.rb speaks: an ActiveRecord model is saved
  # with {LLM::ActiveRecord::Utils.save!} and a Sequel model with
  # {LLM::Sequel::Plugin::Utils.save!}. A context with no record - which is
  # every context that is not backed by a model - has nothing to save, so the
  # step is passed along untouched.
  #
  # The write is best effort. A failure is warned about rather than raised,
  # because this runs inside the request that has just completed, and a stale
  # checkpoint is a smaller failure than a turn that ends because the
  # database was busy.
  #
  # @example Extend the stream an agent was given
  #   stream = MyStream.new
  #   stream.extend(LLM::Step)
  #   agent.talk("Hello", stream: stream)
  #
  # @note `extend` puts this module above the stream's own class, so a
  #   stream that overrides `on_step` for its own purposes is still called
  #   once this module has saved, as long as it calls `super` in turn.
  #
  # @see LLM::Stream#on_step
  # @see LLM::ActiveRecord::Utils.save!
  module Step
    ##
    # Saves the conversation the context holds, then passes the step along.
    #
    # @param [LLM::Context] ctx
    #  The context the request belongs to
    # @param [LLM::Response] res
    #  The response for the request that completed
    # @return [nil]
    def on_step(ctx, res)
      record = ctx.record
      record.nil? ? nil : save!(record, ctx)
      super
    rescue => e
      warn "llm.rb: could not save the conversation: #{e.class}: #{e.message}"
      nil
    end

    private

    ##
    # Saves the record the way its ORM expects.
    #
    # A record that is neither ORM, or that does not carry the options the
    # plugins install, is left alone: llm.rb speaks to both of them, and a
    # context bound to something else has nothing here to save.
    #
    # @param [Object] record
    # @param [LLM::Context] ctx
    # @return [void]
    def save!(record, ctx)
      return unless record.class.respond_to?(:llm_plugin_options)
      options = record.class.llm_plugin_options
      if active_record?(record)
        LLM::ActiveRecord::Utils.save!(record, ctx, options)
      elsif sequel?(record)
        LLM::Sequel::Plugin::Utils.save!(record, ctx, options)
      end
    end

    ##
    # @param [Object] record
    # @return [Boolean]
    def active_record?(record)
      defined?(::ActiveRecord::Base) && record.is_a?(::ActiveRecord::Base)
    end

    ##
    # @param [Object] record
    # @return [Boolean]
    def sequel?(record)
      defined?(::Sequel::Model) && record.is_a?(::Sequel::Model)
    end
  end
end
