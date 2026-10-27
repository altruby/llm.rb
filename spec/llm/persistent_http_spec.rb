# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Transport::PersistentHTTP do
  let(:options) do
    {host: "api.example.com", port: 443, timeout: 60, connect_timeout: 5, ssl: true}
  end
  let(:transport) { described_class.new(**options) }
  let(:pool_class) do
    Class.new do
      attr_accessor :read_timeout, :open_timeout

      def initialize(name: nil)
        @name = name
      end
    end
  end

  before { stub_const("Net::HTTP::Persistent", pool_class) }

  describe "#client" do
    it "builds a pool on first use, configured from the transport" do
      expect(transport.send(:client).read_timeout).to eq(60)
    end

    it "reuses one pool for the life of the transport" do
      expect(transport.send(:client)).to be(transport.send(:client))
    end

    it "does not share a pool with another transport on the same endpoint" do
      other = described_class.new(**options)
      expect(transport.send(:client)).not_to be(other.send(:client))
    end
  end
end
