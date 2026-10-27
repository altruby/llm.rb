# frozen_string_literal: true

class LLM::Schema
  ##
  # The {LLM::Schema::Object LLM::Schema::Object} class represents an
  # object value in a JSON schema. It is a subclass of
  # {LLM::Schema::Leaf LLM::Schema::Leaf} and provides methods that
  # can act as constraints.
  class Object < Leaf
    ##
    # @return [Hash]
    attr_reader :properties

    ##
    # @param [Hash] properties
    #  A hash of properties
    # @return [LLM::Schema::Object]
    def initialize(properties)
      @properties = LLM::Object.new
      properties.each { set!(_1, _2) }
    end

    ##
    # Get a property
    # @return [LLM::Schema::Leaf]
    def [](key)
      properties[key]
    end

    ##
    # Set a property
    # @return [void]
    def []=(key, val)
      set!(key, val)
    end

    ##
    # @return [Hash]
    def to_h
      super.merge!({type: "object", properties: unwrap(properties), required: required_items})
    end

    ##
    # @raise [TypeError]
    #  When given an object other than Object
    # @return [LLM::Schema::Object]
    #  Returns self
    def merge!(other)
      raise TypeError, "expected #{self.class} but got #{other.class}" unless self.class === other
      other.properties.each { |key, val| self[key] = val }
      self
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(to_h, ...)
    end

    ##
    # @return [Array<String>]
    def keys
      @properties.keys
    end

    private

    ##
    # @api private
    def set!(key, val)
      val.index = @properties.size
      properties[key] = val
    end

    ##
    # @api private
    def required_items
      @properties.filter_map { _2.required? ? _1 : nil }
    end

    ##
    # @api private
    # @param [Object] node
    #  A schema, an {LLM::Object} of properties,
    #  or an Array of either
    # @return [Hash, Array<Hash>]
    def unwrap(node)
      case node
      when LLM::Schema::Leaf then unwrap(node.to_h)
      when LLM::Object then node.to_h.transform_values { unwrap(_1) }
      when ::Hash then node.to_h { |key, value| [key, unwrap(value)] }
      when ::Array then node.map { unwrap(_1) }
      else node
      end
    end
  end
end
