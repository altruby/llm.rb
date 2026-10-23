# frozen_string_literal: true

require "setup"

RSpec.describe LLM::Function::Ractor::Mailbox do
  let(:task) { ::Ractor.new { :done } }
  let(:result) { ::Ractor.new { ::Ractor.receive } }
  let(:mailbox) { LLM::Function::Ractor::Mailbox.new(task, result) }

  before do
    task.respond_to?(:take) ? task.take : ::Ractor.select(task).last
  end

  it "answers an interrupt for a ractor that has gone with nil" do
    expect(mailbox.interrupt!).to be_nil
  end
end

