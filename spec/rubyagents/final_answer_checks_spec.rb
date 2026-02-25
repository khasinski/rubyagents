# frozen_string_literal: true

require "spec_helper"

RSpec.describe "final_answer_checks" do
  let(:model) { instance_double(Rubyagents::Model) }

  def final_answer_response(answer)
    Rubyagents::ChatMessage.new(
      role: "assistant",
      content: "Thought: Done.\nCode:\n```ruby\nfinal_answer(answer: #{answer.inspect})\n```",
      token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20)
    )
  end

  it "passes when all checks return truthy" do
    allow(model).to receive(:generate).and_return(final_answer_response("4"))

    check = ->(answer, _mem) { answer.include?("4") }
    agent = Rubyagents::CodeAgent.new(model: model, final_answer_checks: [check])
    expect(agent.run("What is 2+2?")).to eq("4")
  end

  it "rejects answer and retries when a check fails" do
    responses = [
      final_answer_response("wrong"),
      final_answer_response("4")
    ]
    allow(model).to receive(:generate).and_return(*responses)

    check = ->(answer, _mem) { answer.include?("4") }
    agent = Rubyagents::CodeAgent.new(model: model, final_answer_checks: [check], max_steps: 5)
    expect(agent.run("What is 2+2?")).to eq("4")
    expect(model).to have_received(:generate).twice
  end

  it "evaluates multiple checks in order" do
    allow(model).to receive(:generate).and_return(final_answer_response("42"))

    check1 = ->(answer, _mem) { answer.length > 0 }
    check2 = ->(answer, _mem) { answer.include?("42") }
    agent = Rubyagents::CodeAgent.new(model: model, final_answer_checks: [check1, check2])
    expect(agent.run("Test")).to eq("42")
  end

  it "provides memory to checks" do
    allow(model).to receive(:generate).and_return(final_answer_response("done"))

    received_memory = nil
    check = ->(answer, mem) { received_memory = mem; true }
    agent = Rubyagents::CodeAgent.new(model: model, final_answer_checks: [check])
    agent.run("Test")
    expect(received_memory).to be_a(Rubyagents::Memory)
  end

  it "includes check number in rejection message" do
    responses = [
      final_answer_response("bad"),
      final_answer_response("good")
    ]
    allow(model).to receive(:generate).and_return(*responses)

    check1 = ->(_a, _m) { true }
    check2 = ->(a, _m) { a == "good" }
    agent = Rubyagents::CodeAgent.new(model: model, final_answer_checks: [check1, check2], max_steps: 5)
    agent.run("Test")

    # The rejection message should have been added as a user message
    messages = agent.memory.to_messages
    rejection = messages.find { |m| m[:role] == "user" && m[:content].include?("rejected by check #2") }
    expect(rejection).not_to be_nil
  end
end
