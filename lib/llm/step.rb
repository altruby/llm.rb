# frozen_string_literal: true

module LLM
  ##
  # Writes the conversation down when a request completes.
  #
  # {LLM::Step LLM::Step} is prepended onto a stream's singleton class by
  # {LLM::Stream.try}, so a conversation bound to a record is saved as it goes:
  # a turn that is interrupted - by a crash, by a deploy, or by a provider that
  # refuses - can be continued rather than started over.
  #
  # It saves through the record the context is bound to ({LLM::Context#record}),
  # and it knows both the ORMs llm.rb speaks: an ActiveRecord model is saved
  # with {LLM::ActiveRecord::Utils.save!} and a Sequel model with
  # {LLM::Sequel::Plugin::Utils.save!}. A context with no record - which is
  # every context that is not backed by a model - has nothing to save, and
  # neither has a record that carries neither plugin, so the step is passed
  # along untouched.
  #
  # All of this is one method on purpose. The module is put onto an object the
  # caller owns, and a helper would be one more name on that object for as long
  # as it lives.
  #
  # The write is best effort, and a failure is reported rather than raised:
  # this runs inside the request that has just completed, and a stale checkpoint
  # is a smaller failure than a turn that ends because the database was busy.
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
      if record and record.class.respond_to?(:llm_plugin_options)
        options = record.class.llm_plugin_options
        if defined?(::ActiveRecord::Base) and ::ActiveRecord::Base === record
          LLM::ActiveRecord::Utils.save!(record, ctx, options)
        elsif defined?(::Sequel::Model) and ::Sequel::Model === record
          LLM::Sequel::Plugin::Utils.save!(record, ctx, options)
        end
      end
      super
    rescue => e
      warn "llm.rb: could not save the conversation: #{e.class}: #{e.message}"
      nil
    end
  end
end
