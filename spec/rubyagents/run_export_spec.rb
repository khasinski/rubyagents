# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Run export (to_h / to_json)" do
  let(:token_usage) { Rubyagents::TokenUsage.new(input_tokens: 100, output_tokens: 50) }

  describe Rubyagents::TokenUsage do
    it "serializes to hash" do
      h = token_usage.to_h
      expect(h).to eq({ input_tokens: 100, output_tokens: 50 })
    end
  end

  describe Rubyagents::ToolCallFunction do
    it "serializes to hash" do
      f = Rubyagents::ToolCallFunction.new(name: "search", arguments: { q: "ruby" })
      expect(f.to_h).to eq({ name: "search", arguments: { q: "ruby" } })
    end
  end

  describe Rubyagents::ToolCall do
    it "serializes to hash including function" do
      tc = Rubyagents::ToolCall.new(
        id: "call_1",
        function: Rubyagents::ToolCallFunction.new(name: "echo", arguments: { msg: "hi" })
      )
      h = tc.to_h
      expect(h[:id]).to eq("call_1")
      expect(h[:function]).to eq({ name: "echo", arguments: { msg: "hi" } })
    end
  end

  describe Rubyagents::ActionStep do
    it "serializes with type discriminator" do
      step = Rubyagents::ActionStep.new(
        step_number: 1, thought: "thinking", code: "puts 1",
        observation: "1", duration: 1.5, token_usage: token_usage
      )
      h = step.to_h
      expect(h[:type]).to eq("action")
      expect(h[:step_number]).to eq(1)
      expect(h[:thought]).to eq("thinking")
      expect(h[:code]).to eq("puts 1")
      expect(h[:observation]).to eq("1")
      expect(h[:token_usage]).to eq({ input_tokens: 100, output_tokens: 50 })
    end

    it "omits nil optional fields" do
      step = Rubyagents::ActionStep.new(step_number: 1, thought: "thinking")
      h = step.to_h
      expect(h).not_to have_key(:code)
      expect(h).not_to have_key(:tool_calls)
      expect(h).not_to have_key(:observation)
      expect(h).not_to have_key(:error)
      expect(h).not_to have_key(:token_usage)
    end

    it "serializes tool_calls" do
      tc = Rubyagents::ToolCall.new(
        id: "c1",
        function: Rubyagents::ToolCallFunction.new(name: "web", arguments: {})
      )
      step = Rubyagents::ActionStep.new(step_number: 1, thought: "t", tool_calls: [tc])
      expect(step.to_h[:tool_calls]).to eq([{ id: "c1", function: { name: "web", arguments: {} } }])
    end
  end

  describe Rubyagents::PlanningStep do
    it "serializes with type discriminator" do
      step = Rubyagents::PlanningStep.new(plan: "Step 1\nStep 2", duration: 2.0, token_usage: token_usage)
      h = step.to_h
      expect(h[:type]).to eq("planning")
      expect(h[:plan]).to eq("Step 1\nStep 2")
    end
  end

  describe Rubyagents::UserMessage do
    it "serializes with type discriminator" do
      msg = Rubyagents::UserMessage.new(content: "hello")
      expect(msg.to_h).to eq({ type: "user_message", content: "hello" })
    end
  end

  describe Rubyagents::Memory do
    it "serializes to hash and JSON" do
      mem = Rubyagents::Memory.new(system_prompt: "You are helpful", task: "Count to 3")
      mem.add_step(thought: "I will count", code: "puts (1..3).to_a.join(', ')",
                   observation: "1, 2, 3", duration: 1.0, token_usage: token_usage)

      h = mem.to_h
      expect(h[:task]).to eq("Count to 3")
      expect(h[:system_prompt]).to eq("You are helpful")
      expect(h[:steps].size).to eq(1)
      expect(h[:steps].first[:type]).to eq("action")
      expect(h[:total_tokens]).to eq({ input_tokens: 100, output_tokens: 50 })

      json = mem.to_json
      parsed = JSON.parse(json)
      expect(parsed["task"]).to eq("Count to 3")
      expect(parsed["steps"].size).to eq(1)
    end
  end

  describe Rubyagents::RunResult do
    it "serializes to hash and JSON" do
      step = Rubyagents::ActionStep.new(step_number: 1, thought: "done", observation: "42")
      result = Rubyagents::RunResult.new(
        output: "42", state: "success", steps: [step],
        token_usage: token_usage, timing: 3.5
      )

      h = result.to_h
      expect(h[:output]).to eq("42")
      expect(h[:state]).to eq("success")
      expect(h[:steps].size).to eq(1)
      expect(h[:timing]).to eq(3.5)

      json = result.to_json
      parsed = JSON.parse(json)
      expect(parsed["state"]).to eq("success")
    end
  end
end
