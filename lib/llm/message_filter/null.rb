# frozen_string_literal: true

class LLM::MessageFilter
  ##
  # An {LLM::MessageFilter::Null LLM::MessageFilter::Null} is a
  # filter that does nothing. It is used as the default when
  # no filter strategy is configured.
  #
  # It returns the given message unchanged.
  class Null < self
    ##
    # @param [LLM::Message] message
    #  The message to filter
    # @param [Hash] opts
    #  Ignored
    # @return [LLM::Message]
    def call(message:, **opts)
      message
    end
  end
end
