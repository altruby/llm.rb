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
      stream.define_singleton_method(:on_step) { |res| steps << res }
      ctx.talk("hello")
      expect(steps).to eq([response])
    end

    it "calls the callback with the response" do
      called = nil
      stream.define_singleton_method(:on_step) { |res| called = res }
      ctx.talk("hello")
      expect(called).to be(response)
    end
  end

  describe "a disabled stream" do
    let(:stream) { LLM::Stream::Disabled.new }

    it "is still told when a request completes" do
      steps = []
      stream.extend(Module.new do
        define_method(:on_step) { |res| steps << res }
      end)
      ctx.talk("hello")
      expect(steps).to eq([response])
    end

    it "reaches the base callback through super" do
      reached = []
      stream.extend(Module.new do
        define_method(:on_step) do |res|
          reached << res
          super(res)
        end
      end)
      ctx.talk("hello")
      expect(reached).to eq([response])
      expect(stream.on_step(response)).to be_nil
    end
  end

  describe "the base callback" do
    it "returns nil" do
      expect(stream.on_step(response)).to be_nil
    end
  end
end
