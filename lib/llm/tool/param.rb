# frozen_string_literal: true

class LLM::Tool
  ##
  # The {LLM::Tool::Param LLM::Tool::Param} module extends the
  # {LLM::Tool LLM::Tool} class with a "param" method that can
  # define a parameter for simple types. For complex types, use
  # {LLM::Tool.params LLM::Tool.params} instead.
  #
  # @example
  #   class Greeter < LLM::Tool
  #     name "greeter"
  #     description "Greets the user"
  #     parameter :name, String, "The user's name"
  #     required %i[name]
  #
  #     def call(name:)
  #       puts "Hello, #{name}!"
  #     end
  #   end
  module Param
    ##
    # @param name [Symbol]
    #   The name of a parameter
    # @param type [LLM::Schema::Leaf, Class, Proc]
    #   The parameter type (eg String). A proc is called for the type
    #   when the parameters are read, so a type that can only be known
    #   at runtime does not have to be known when the class is defined.
    # @param description [String]
    #   The description of a property
    # @param options [Hash]
    #   A hash of options for the parameter. Each option is applied to the
    #   leaf the type resolves to, so any setting a leaf accepts works here,
    #   such as `required:`, `default:`, `enum:`, and the range settings
    #   `min:` and `max:` that an integer, number, or string leaf supports.
    # @option options [Boolean] :required
    #   Whether or not the parameter is required
    # @option options [Object] :default
    #   The default value for a given property
    # @option options [Array<String>] :enum
    #   One or more possible values for a param
    def param(name, type, description, options = {})
      lock do
        function.params do |schema|
          resolved = Utils.resolve(schema, type)
          schema.object(name => Utils.setup(resolved, description, options))
        end
      end
    end
    alias_method :parameter, :param

    ##
    # Mark existing parameters as required.
    # @param names [Array<Symbol,String>]
    # @return [LLM::Schema::Object]
    def required(names)
      lock do
        function.params.tap do |schema|
          [*names].each { Utils.fetch(schema.properties, _1).required }
        end
      end
    end

    ##
    # Set default values for parameters.
    # @param [Hash] defaults
    # @return [LLM::Schema::Object]
    def defaults(defaults)
      lock do
        function.params.tap do |schema|
          defaults.each do |name, value|
            leaf = Utils.fetch(schema.properties, name)
            leaf.owner = self
            leaf.default(value)
          end
        end
      end
    end

    ##
    # @api private
    module Utils
      extend self

      def resolve(schema, type)
        LLM::Schema::Utils.resolve(schema, type)
      end

      def setup(leaf, description, options)
        options = {description:}.merge(options)
        options.each do |name, value|
          (value == true) ? leaf.public_send(name) : leaf.public_send(name, *value)
        end
        leaf
      end

      def fetch(properties, name)
        properties[name] || properties.fetch(name.to_s)
      end
    end
  end
end
