# frozen_string_literal: true

require "setup"

RSpec.describe "LLM::Stream#on_step" do
  let(:provider) { LLM.deepseek(key: "test") }
  let(:response) { double("response", choices: []) }
  let(:stream) { LLM::Stream.new }
  let(:ctx) do
    LLM::Context.new(provider, mode: :completions, model: "deepseek-chat", stream: stream)
  end

  ##
  # The request is stubbed, so this is the response the runtime would have
  # appended to `@messages` by the time it emits the callback. The first
  # element is what a real request returns as its new messages.
  before do
    allow(ctx).to receive(:complete) { |prompt, params| [[], params, response] }
  end

  describe "a context" do
    it "tells the stream once when a request completes" do
      steps = []
      stream.define_singleton_method(:on_step) { |ctx, res| steps << [ctx, res] }
      ctx.talk("hello")
      expect(steps).to eq([[ctx, response]])
    end

    it "passes the response, and the context it belongs to" do
      called = nil
      stream.define_singleton_method(:on_step) { |ctx, res| called = [ctx, res] }
      ctx.talk("hello")
      expect(called).to eq([ctx, response])
    end
  end

  describe "a disabled stream" do
    let(:stream) { LLM::Stream::Disabled.new }

    it "is still told when a request completes" do
      steps = []
      stream.extend(Module.new do
        define_method(:on_step) { |ctx, res| steps << [ctx, res] }
      end)
      ctx.talk("hello")
      expect(steps).to eq([[ctx, response]])
    end

    it "reaches the base callback through super" do
      reached = []
      stream.extend(Module.new do
        define_method(:on_step) do |ctx, res|
          reached << [ctx, res]
          super(ctx, res)
        end
      end)
      ctx.talk("hello")
      expect(reached).to eq([[ctx, response]])
      expect(stream.on_step(ctx, response)).to be_nil
    end
  end

  describe "the base callback" do
    it "returns nil" do
      expect(stream.on_step(ctx, response)).to be_nil
    end
  end

  describe LLM::Step do
    let(:stream) do
      Class.new(LLM::Stream) do
        attr_reader :steps

        def initialize
          @steps = []
        end

        def on_step(ctx, res)
          @steps << [ctx, res]
        end
      end.new
    end

    it "is extended onto the stream by the context" do
      ctx.talk("hello")
      expect(stream.singleton_class.include?(described_class)).to be(true)
    end

    it "passes the step along when the context has no record" do
      ctx.talk("hello")
      expect(stream.steps).to eq([[ctx, response]])
    end

    it "passes the step along for a record that carries no plugin" do
      record = Class.new { def self.llm_plugin_options = {} }.new
      allow(ctx).to receive(:record).and_return(record)
      ctx.talk("hello")
      expect(stream.steps).to eq([[ctx, response]])
    end
  end
end
