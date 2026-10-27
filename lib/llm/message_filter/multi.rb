# frozen_string_literal: true

class LLM::MessageFilter
  ##
  # A filter that fans out to multiple
  # other filters, so a message can be
  # filtered multiple times by different
  # filters.
  # @example
  #   filter = LLM::MessageFilter.multi(
  #     llm,
  #     FilterOne,
  #     FilterTwo
  #   )
  class Multi < self
    ##
    # Returns the filters under the
    # supervision of Multi
    # @return [Array<LLM::MessageFilter>]
    attr_reader :filters

    ##
    # @param [Array<LLM::MessageFilter>] filters
    #  The filters to fan out to.
    #  A Multi has no provider of its own.
    def initialize(*filters)
      super(nil)
      @filters = filters
    end

    ##
    # @param (see LLM::MessageFilter#call)
    # @return (see LLM::MessageFilter#call)
    def call(message:, **opts)
      @filters.map do
        message = it.call(message:, **opts)
      end.last
    end
  end
end
