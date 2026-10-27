#!/usr/bin/env ruby
# frozen_string_literal: true

require "llm"
require "llm/tools"
require "fileutils"

class Agent < LLM::Agent
  require_relative "subagent"

  set name: "llm.rb agent",
      description: "works with docs",
      tools: [SubAgent],
      path: File.join(__dir__, "..", "..", "contexts", "scribe.json"),
      tracer: proc { LLM::Tracer.pretty(llm) }

  def changelog
    talk("Let's update the changelog")
  end
end

def main(argv)
  llm   = LLM.deepseek
  agent = Agent.new(llm)
  if argv[0] == "console"
    agent.console
  elsif agent.respond_to?(argv[0])
    agent.method(argv[0]).call(*argv[1..])
    agent.console
  else
    warn "agent: expected audit, improvements, review, or console but got #{argv[0]}"
    exit 1
  end
end
main(ARGV)
