# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rubyagents::Memory do
  let(:memory) { described_class.new(system_prompt: "You are helpful.", task: "Do something") }

  describe "#add_step" do
    it "adds an action step" do
      step = memory.add_step(thought: "thinking", code: "puts 1", observation: "1")
      expect(step).to be_a(Rubyagents::ActionStep)
      expect(step.step_number).to eq(1)
      expect(step.thought).to eq("thinking")
    end

    it "increments step numbers" do
      memory.add_step(thought: "first")
      step = memory.add_step(thought: "second")
      expect(step.step_number).to eq(2)
    end

    it "tracks token usage" do
      usage = Rubyagents::TokenUsage.new(input_tokens: 100, output_tokens: 50)
      memory.add_step(thought: "t", token_usage: usage, duration: 1.5)
      expect(memory.total_tokens.total_tokens).to eq(150)
      expect(memory.total_duration).to eq(1.5)
    end

    it "supports tool_calls field" do
      tc = [Rubyagents::ToolCall.new(id: "1", function: Rubyagents::ToolCallFunction.new(name: "test", arguments: {}))]
      step = memory.add_step(thought: "t", tool_calls: tc)
      expect(step.tool_calls).to eq(tc)
    end
  end

  describe "#add_plan" do
    it "adds a planning step" do
      step = memory.add_plan(plan: "1. Do this\n2. Do that")
      expect(step).to be_a(Rubyagents::PlanningStep)
    end
  end

  describe "#add_user_message" do
    it "adds a UserMessage to steps" do
      memory.add_user_message("follow up question")
      expect(memory.steps.last).to be_a(Rubyagents::UserMessage)
      expect(memory.steps.last.content).to eq("follow up question")
    end
  end

  describe "#action_steps" do
    it "filters to only ActionSteps" do
      memory.add_step(thought: "t1")
      memory.add_plan(plan: "plan")
      memory.add_step(thought: "t2")
      expect(memory.action_steps.size).to eq(2)
    end
  end

  describe "#progress_summary" do
    it "returns summary when no steps" do
      expect(memory.progress_summary).to eq("No steps completed yet.")
    end

    it "summarizes completed steps" do
      memory.add_step(thought: "Did research", observation: "got results")
      memory.add_step(thought: "Failed attempt", error: "timeout")
      summary = memory.progress_summary
      expect(summary).to include("Did research")
      expect(summary).to include("[done]")
      expect(summary).to include("[failed]")
    end
  end

  describe "#to_messages" do
    it "builds basic message history" do
      messages = memory.to_messages
      expect(messages.first[:role]).to eq("system")
      expect(messages.last[:role]).to eq("user")
      expect(messages.last[:content]).to eq("Do something")
    end

    it "includes action steps as assistant/user pairs" do
      memory.add_step(thought: "thinking", code: "x = 1", observation: "=> 1")
      messages = memory.to_messages
      assistant_msgs = messages.select { |m| m[:role] == "assistant" }
      expect(assistant_msgs.size).to eq(1)
      expect(assistant_msgs.first[:content]).to include("Thought: thinking")
      expect(assistant_msgs.first[:content]).to include("```ruby")
    end

    it "includes error messages with retry guidance" do
      memory.add_step(thought: "try", code: "bad", error: "SyntaxError")
      messages = memory.to_messages
      error_msg = messages.find { |m| m[:content]&.include?("Error:") }
      expect(error_msg[:content]).to include("retry")
    end

    it "includes UserMessage entries" do
      memory.add_step(thought: "done")
      memory.add_user_message("new question")
      messages = memory.to_messages
      user_msgs = messages.select { |m| m[:role] == "user" }
      expect(user_msgs.last[:content]).to eq("new question")
    end

    it "includes planning steps" do
      memory.add_plan(plan: "Step 1")
      messages = memory.to_messages
      plan_msg = messages.find { |m| m[:content]&.include?("Plan:") }
      expect(plan_msg).not_to be_nil
      proceed_msg = messages.find { |m| m[:content]&.include?("proceed") }
      expect(proceed_msg).not_to be_nil
    end

    it "handles tool_calls in assistant messages" do
      tc = [Rubyagents::ToolCall.new(id: "1", function: Rubyagents::ToolCallFunction.new(name: "search", arguments: { q: "test" }))]
      memory.add_step(thought: "searching", tool_calls: tc, observation: "results")
      messages = memory.to_messages
      assistant_msg = messages.find { |m| m[:role] == "assistant" && m[:tool_calls] }
      expect(assistant_msg).not_to be_nil
      expect(assistant_msg[:tool_calls].first.function.name).to eq("search")
    end
  end

  describe "#return_full_code" do
    it "concatenates all code blocks" do
      memory.add_step(thought: "t1", code: "x = 1")
      memory.add_step(thought: "t2", code: "y = 2")
      expect(memory.return_full_code).to eq("x = 1\n\ny = 2")
    end
  end

  describe "token tracking" do
    it "accumulates across multiple steps" do
      u1 = Rubyagents::TokenUsage.new(input_tokens: 100, output_tokens: 50)
      u2 = Rubyagents::TokenUsage.new(input_tokens: 200, output_tokens: 100)
      memory.add_step(thought: "t1", token_usage: u1)
      memory.add_step(thought: "t2", token_usage: u2)
      expect(memory.total_tokens.input_tokens).to eq(300)
      expect(memory.total_tokens.output_tokens).to eq(150)
    end
  end
end
