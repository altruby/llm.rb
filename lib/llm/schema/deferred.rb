# frozen_string_literal: true

class LLM::Schema
  ##
  # {LLM::Schema::Deferred LLM::Schema::Deferred} is a placeholder for a
  # leaf that is resolved when the schema is rendered.
  #
  # A parameter type that can only be known at runtime - an enum of the
  # keys a store holds right now, for example - is given as a proc. The
  # proc is called when the schema is rendered rather than when the class
  # that declares the parameter is defined, so declaring a tool does not
  # touch whatever the type depends on:
  #
  #   parameter :fruit, proc { Enum[*Fruit.kinds]}, "A fruit", required: true
  #
  # Whatever the proc returns is resolved in turn, so it can return a
  # leaf, a class, or an array of either.
  #
  # @api private
  class Deferred < Leaf
    ##
    # @param [Proc] block
    #  A block that returns the leaf to resolve to
    # @return [LLM::Schema::Deferred]
    def initialize(&block)
      super()
      @block = block
    end

    ##
    # @return [Hash]
    def to_h
      resolve.to_h
    end

    ##
    # @param [Hash] options
    # @return [String]
    def to_json(options = {})
      resolve.to_h.to_json(options)
    end

    ##
    # @return [String]
    def to_s
      resolve.to_s
    end

    private

    ##
    # Returns the leaf the block resolves to, with the settings that
    # were given to the placeholder applied to it.
    #
    # The settings live on the placeholder, because they are given
    # before the leaf it stands for exists.
    # @return [LLM::Schema::Leaf]
    def resolve
      leaf = @block.call
      leaf.description(@description) if @description
      leaf.default(@default) unless @default.nil?
      leaf.enum(*@enum) if @enum
      leaf.const(@const) unless @const.nil?
      leaf.required if required?
      leaf
    end
  end
end
