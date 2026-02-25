# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rubyagents::ToolCallingAgent do
  let(:model) { instance_double(Rubyagents::Model) }

  describe "#run" do
    it "handles final_answer tool call" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "I know the answer.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "42" })
          )
        ]
      )

      allow(model).to receive(:generate).and_return(response)

      agent = described_class.new(model: model)
      result = agent.run("What is the meaning of life?")
      expect(result).to eq("42")
    end

    it "processes tool calls and returns results" do
      test_tool = Rubyagents.tool(:multiply, "Multiplies two numbers",
                                  a: { type: :integer, description: "First number" },
                                  b: { type: :integer, description: "Second number" }) do |a:, b:|
        (a.to_i * b.to_i).to_s
      end

      # First response: call the tool
      response1 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Let me multiply.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "multiply", arguments: { "a" => 6, "b" => 7 })
          )
        ]
      )

      # Second response: final answer
      response2 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "The result is 42.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 30, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_2",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "42" })
          )
        ]
      )

      allow(model).to receive(:generate).and_return(response1, response2)

      agent = described_class.new(model: model, tools: [test_tool])
      result = agent.run("What is 6 * 7?")
      expect(result).to eq("42")
    end

    it "handles unknown tools gracefully" do
      response1 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Trying unknown tool.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "nonexistent", arguments: {})
          )
        ]
      )

      response2 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Let me try differently.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 30, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_2",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "recovered" })
          )
        ]
      )

      allow(model).to receive(:generate).and_return(response1, response2)

      agent = described_class.new(model: model)
      result = agent.run("Test unknown tool")
      expect(result).to eq("recovered")
    end

    it "returns RunResult when return_full_result is true" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Done.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "result" })
          )
        ]
      )

      allow(model).to receive(:generate).and_return(response)

      agent = described_class.new(model: model)
      result = agent.run("Test", return_full_result: true)
      expect(result).to be_a(Rubyagents::RunResult)
      expect(result.success?).to be true
      expect(result.output).to eq("result")
    end

    it "handles response with no tool_calls as a thought step" do
      response1 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Let me think about this...",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
        tool_calls: nil
      )

      response2 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Got it.",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 30, output_tokens: 20),
        tool_calls: [
          Rubyagents::ToolCall.new(
            id: "call_1",
            function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => "thought first" })
          )
        ]
      )

      allow(model).to receive(:generate).and_return(response1, response2)

      agent = described_class.new(model: model)
      result = agent.run("Test thinking")
      expect(result).to eq("thought first")
    end
  end
end
