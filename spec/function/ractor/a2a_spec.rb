# frozen_string_literal: true

require "setup"

RSpec.describe "ractor: a2a tools" do
  before { WebMock.disable! }
  after { WebMock.enable! }

  let(:server) { File.expand_path("../../support/a2a/server.rb", __dir__) }
  let(:port) { 20_000 + rand(20_000) }

  let!(:pid) do
    Process.spawn(
      RbConfig.ruby,
      server,
      port.to_s,
      out: File::NULL,
      err: File::NULL
    ).tap { sleep 1 }
  end

  after do
    Process.kill("KILL", pid)
    Process.wait(pid)
  end

  shared_examples "an A2A tool in a ractor" do
    let(:function) do
      LLM::Tool.a2a(a2a, a2a.card.skills[0]).function.dup.tap do |fn|
        fn.id = "call_1"
        fn.arguments = {"input" => "hi"}
      end
    end
    let(:result) { function.task(:ractor).wait.to_h }

    it "returns the task" do
      expect(result[:value][:task].task.artifacts[0].parts[0].text).to eq("Hello, World!")
    end
  end

  context "with the rest binding" do
    let(:a2a) { LLM::A2A.rest(url: "http://127.0.0.1:#{port}") }

    it_behaves_like "an A2A tool in a ractor"
  end

  context "with the jsonrpc binding" do
    let(:a2a) { LLM::A2A.jsonrpc(url: "http://127.0.0.1:#{port}") }

    it_behaves_like "an A2A tool in a ractor"
  end
end
