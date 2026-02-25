# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent#step" do
  let(:model) { instance_double(Rubyagents::Model) }

  def tool_calling_response(answer: nil, content: "Thinking...")
    tc = answer ? [
      Rubyagents::ToolCall.new(
        id: "call_1",
        function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => answer })
      )
    ] : nil

    Rubyagents::ChatMessage.new(
      role: "assistant",
      content: content,
      token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
      tool_calls: tc
    )
  end

  it "requires task on first call" do
    agent = Rubyagents::ToolCallingAgent.new(model: model)
    expect { agent.step }.to raise_error(ArgumentError, /task required/)
  end

  it "returns an ActionStep" do
    allow(model).to receive(:generate).and_return(tool_calling_response(answer: "42"))

    agent = Rubyagents::ToolCallingAgent.new(model: model)
    step = agent.step("What is 6*7?")
    expect(step).to be_a(Rubyagents::ActionStep)
  end

  it "loops until done" do
    responses = [
      tool_calling_response(content: "Let me think..."),
      tool_calling_response(answer: "42")
    ]
    allow(model).to receive(:generate).and_return(*responses)

    agent = Rubyagents::ToolCallingAgent.new(model: model)
    agent.step("What is 6*7?")
    expect(agent.done?).to be false

    agent.step
    expect(agent.done?).to be true
    expect(agent.final_answer_value).to eq("42")
  end

  it "raises MaxStepsError when exceeded" do
    allow(model).to receive(:generate).and_return(tool_calling_response(content: "Thinking..."))

    agent = Rubyagents::ToolCallingAgent.new(model: model, max_steps: 2)
    agent.step("Test")
    agent.step
    expect { agent.step }.to raise_error(Rubyagents::MaxStepsError)
  end

  it "accepts user messages on subsequent calls" do
    responses = [
      tool_calling_response(content: "First thought"),
      tool_calling_response(answer: "done")
    ]
    allow(model).to receive(:generate).and_return(*responses)

    agent = Rubyagents::ToolCallingAgent.new(model: model)
    agent.step("Initial task")
    agent.step("Additional context")

    user_messages = agent.memory.steps.select { |s| s.is_a?(Rubyagents::UserMessage) }
    expect(user_messages.map(&:content)).to include("Additional context")
  end

  it "resets state with reset!" do
    allow(model).to receive(:generate).and_return(tool_calling_response(answer: "42"))

    agent = Rubyagents::ToolCallingAgent.new(model: model)
    agent.step("Test")
    expect(agent.done?).to be true

    agent.reset!
    expect(agent.done?).to be false
    expect(agent.final_answer_value).to be_nil
    expect(agent.memory).to be_nil
  end

  it "validates final answer with checks" do
    responses = [
      tool_calling_response(answer: "bad"),
      tool_calling_response(answer: "good")
    ]
    allow(model).to receive(:generate).and_return(*responses)

    check = ->(answer, _mem) { answer == "good" }
    agent = Rubyagents::ToolCallingAgent.new(model: model, final_answer_checks: [check], max_steps: 5)
    agent.step("Test")
    expect(agent.done?).to be false

    agent.step
    expect(agent.done?).to be true
    expect(agent.final_answer_value).to eq("good")
  end
end
