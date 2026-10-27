# frozen_string_literal: true

##
# The {LLM::Registry LLM::Registry} class provides a small API over
# provider model data. It exposes model metadata such as pricing,
# capabilities, modalities, and limits from the registry files
# stored under `data/`. The data is provided by https://models.dev
# and shipped with llm.rb.
class LLM::Registry
  require_relative "registry/model"
  @root = File.join(__dir__, "..", "..").freeze

  ##
  # @raise [LLM::Error]
  #  Might raise an error
  # @param [Symbol] name
  #  A provider name
  # @return [LLM::Registry]
  def self.for(name)
    path = File.join @root, "data", "#{name}.json"
    if File.file?(path)
      new LLM.json.load(File.binread(path))
    else
      raise LLM::NoSuchRegistryError, "no registry found for #{name}"
    end
  end

  ##
  # @param [Hash] blob
  #  A model registry
  # @return [LLM::Registry]
  def initialize(blob)
    @registry = LLM::Object.from(blob)
    @models = @registry.models
  end

  ##
  # Returns the model keys (names) in the registry.
  # @return [Array<String>]
  def keys
    @models.keys
  end

  ##
  # Returns all models as {LLM::Registry::Model} objects.
  # @return [Array<LLM::Registry::Model>]
  def models
    @models.map { |id, data| Model.new(data.merge(id:)) }
  end

  ##
  # @return [Array<String>]
  def env
    @registry.env
  end

  ##
  # @return [LLM::Object]
  #  Returns model costs
  def cost(model:)
    find(model:).cost
  end

  ##
  # @return [LLM::Object]
  #  Returns model modalities
  def modalities(model:)
    find(model:).modalities
  end

  ##
  # @return [LLM::Object]
  #  Returns model limits such as the context window size
  def limit(model:)
    find(model:).limit
  end

  private

  ##
  # Find a model, or raise an error
  # @param [String] model
  #  Model ID
  # @return [LLM::Registry::Model]
  def find(model:)
    data = @models[model]
    if data.nil?
      fallback = find_fallback(model)
      data = @models[fallback]
      raise LLM::NoSuchModelError, "no such model: #{model} (fallback: #{fallback})" if data.nil?
    end
    Model.new(data)
  end

  ##
  # Finds a fallback model name, or "none"
  # @param [String] model_id
  # @return [String]
  def find_fallback(model_id)
    patterns = {/-\d{4}-\d{2}-\d{2}$/ => "", /\A(gpt-.*)-\d{4}$/ => "\\1"}
    find_map(patterns) { model_id.dup.sub!(_1, _2) } || "none"
  end

  ##
  # Similar to `#find` but returns the block's return value
  # @return [Object, nil]
  def find_map(pair)
    result = nil
    pair.each_pair { break if result = yield(_1, _2) }
    result
  end
end
