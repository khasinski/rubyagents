# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rubyagents::CodeAgent do
  let(:model) { instance_double(Rubyagents::Model) }

  describe "#run" do
    it "parses thought and code from response" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: I need to compute the answer.\nCode:\n```ruby\nfinal_answer(answer: \"4\")\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response)

      agent = described_class.new(model: model)
      result = agent.run("What is 2+2?")
      expect(result).to eq("4")
    end

    it "handles multi-step execution" do
      response1 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Let me compute first.\nCode:\n```ruby\nputs 2 + 2\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      response2 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Now I know the answer.\nCode:\n```ruby\nfinal_answer(answer: \"4\")\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 30, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response1, response2)

      agent = described_class.new(model: model)
      result = agent.run("What is 2+2?")
      expect(result).to eq("4")
    end

    it "returns RunResult when return_full_result is true" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Easy.\nCode:\n```ruby\nfinal_answer(answer: \"done\")\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response)

      agent = described_class.new(model: model)
      result = agent.run("Test", return_full_result: true)
      expect(result).to be_a(Rubyagents::RunResult)
      expect(result.success?).to be true
      expect(result.output).to eq("done")
    end

    it "handles max_steps exceeded" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Still working.\nCode:\n```ruby\nputs 'working'\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response)

      agent = described_class.new(model: model, max_steps: 2)
      result = agent.run("Infinite task", return_full_result: true)
      expect(result.state).to eq("max_steps")
    end

    it "handles errors in code execution" do
      response1 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Try bad code.\nCode:\n```ruby\nraise 'boom'\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      response2 = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Fix it.\nCode:\n```ruby\nfinal_answer(answer: \"fixed\")\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 30, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response1, response2)

      agent = described_class.new(model: model)
      result = agent.run("Retry test")
      expect(result).to eq("fixed")
    end
  end

  describe "step_callbacks" do
    it "invokes callbacks after each step" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Done.\nCode:\n```ruby\nfinal_answer(answer: \"ok\")\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      allow(model).to receive(:generate).and_return(response)

      steps_seen = []
      callback = ->(step, agent:) { steps_seen << step }

      agent = described_class.new(model: model, step_callbacks: [callback])
      agent.run("Test")
      expect(steps_seen.size).to eq(1)
      expect(steps_seen.first).to be_a(Rubyagents::ActionStep)
    end
  end

  describe "#interrupt" do
    it "raises InterruptError on next step" do
      response = Rubyagents::ChatMessage.new(
        role: "assistant",
        content: "Thought: Working.\nCode:\n```ruby\nputs 'hi'\n```",
        token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
      )

      agent = described_class.new(model: model)

      # Interrupt after first generate call, so it triggers on step 2
      call_count = 0
      allow(model).to receive(:generate) do
        call_count += 1
        agent.interrupt if call_count == 1
        response
      end

      expect { agent.run("Test") }.to raise_error(Rubyagents::InterruptError)
    end
  end
end
