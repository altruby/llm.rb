# frozen_string_literal: true

class SubAgent < LLM::Tool
  name "subagent"
  description "edit a file with a subagent "
  parameter :file, Enum["CHANGELOG.md"], "the file to edit"

  def call(file:)
    options  = {tracer: LLM::Tracer.pretty(llm),
                instructions: File.read(prompts[file]),
                tools: LLM::Tool.subclasses}
    subagent = LLM::Agent.new(llm, options)
    case file
    when "CHANGELOG.md"
      res = subagent.talk("let's update the changelog")
      {content: res.content}
    else
      raise LLM::Error, "'#{file}' is not a valid file"
    end
  end

  private

  def llm
    LLM.deepseek
  end

  def prompts
    {"CHANGELOG.md" => File.join(__dir__, "changelog.md") }
  end
end
