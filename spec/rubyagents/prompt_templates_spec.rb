# frozen_string_literal: true

require "spec_helper"

RSpec.describe "prompt customization" do
  let(:model) { instance_double(Rubyagents::Model) }

  def final_answer_response(answer)
    Rubyagents::ChatMessage.new(
      role: "assistant",
      content: "Thought: Done.\nCode:\n```ruby\nfinal_answer(answer: #{answer.inspect})\n```",
      token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
    )
  end

  describe Rubyagents::PromptTemplates do
    it "defaults all fields to nil" do
      pt = Rubyagents::PromptTemplates.new
      expect(pt.system_prompt).to be_nil
      expect(pt.planning_initial).to be_nil
      expect(pt.planning_update).to be_nil
    end

    it "accepts keyword arguments" do
      pt = Rubyagents::PromptTemplates.new(system_prompt: "custom")
      expect(pt.system_prompt).to eq("custom")
    end
  end

  describe "instructions" do
    it "appends instructions to system prompt" do
      allow(model).to receive(:generate).and_return(final_answer_response("bonjour"))

      agent = Rubyagents::CodeAgent.new(model: model, instructions: "Always answer in French.")
      agent.run("Hello")

      expect(agent.memory.system_prompt).to include("Always answer in French.")
    end

    it "appends instructions for ToolCallingAgent" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Done.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "ok" })
          )
        ]
      )
      allow(model).to receive(:generate).and_return(response)

      agent = Rubyagents::ToolCallingAgent.new(model: model, instructions: "Be concise.")
      agent.run("Test")

      system_msg = agent.memory.system_prompt
      expect(system_msg).to include("Be concise.")
    end
  end

  describe "custom system prompt" do
    it "substitutes {{tool_descriptions}} in custom prompt" do
      allow(model).to receive(:generate).and_return(final_answer_response("ok"))

      templates = Rubyagents::PromptTemplates.new(system_prompt: "Custom agent. Tools: {{tool_descriptions}}")
      agent = Rubyagents::CodeAgent.new(model: model, prompt_templates: templates)
      agent.run("Test")

      system_msg = agent.memory.system_prompt
      expect(system_msg).to start_with("Custom agent. Tools:")
      expect(system_msg).to include("final_answer")
    end
  end

  describe "custom planning templates" do
    it "uses custom planning_initial prompt" do
      plan_response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "1. Do the thing",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )
      answer_response = final_answer_response("done")

      call_count = 0
      allow(model).to receive(:generate) do |messages, **_|
        call_count += 1
        if call_count == 1
          # Planning call -- verify the system prompt was customized
          expect(messages[0][:content]).to eq("Custom planner")
          plan_response
        else
          answer_response
        end
      end

      templates = Rubyagents::PromptTemplates.new(planning_initial: "Custom planner")
      agent = Rubyagents::CodeAgent.new(model: model, prompt_templates: templates, planning_interval: 3)
      agent.run("Test")
    end

    it "uses custom planning_update prompt" do
      plan_response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "1. Plan step",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )
      work_response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Working.\nCode:\n```ruby\nputs 'hi'\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )
      answer_response = final_answer_response("done")

      call_count = 0
      allow(model).to receive(:generate) do |messages, **_|
        call_count += 1
        case call_count
        when 1 then plan_response       # initial plan (step 1)
        when 2 then work_response        # step 1 work
        when 3 then work_response        # step 2 work
        when 4                           # update plan (step 3)
          expect(messages[0][:content]).to eq("Updated planner")
          plan_response
        else answer_response             # step 3 work
        end
      end

      templates = Rubyagents::PromptTemplates.new(planning_update: "Updated planner")
      agent = Rubyagents::CodeAgent.new(model: model, prompt_templates: templates, planning_interval: 2, max_steps: 5)
      agent.run("Test")
    end
  end
end
