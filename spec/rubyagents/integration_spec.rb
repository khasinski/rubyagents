# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Integration with Ollama", :ollama do
  before(:all) do
    # Check if Ollama is available
    uri = URI("http://localhost:11434/api/tags")
    begin
      response = Net::HTTP.get_response(uri)
      skip "Ollama not running" unless response.is_a?(Net::HTTPSuccess)
      tags = JSON.parse(response.body)
      models = tags["models"]&.map { |m| m["name"] } || []
      skip "qwen2.5:3b not available" unless models.any? { |m| m.start_with?("qwen2.5:3b") }
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      skip "Ollama not running"
    end
  end

  # Re-enable UI for integration tests to see actual agent behavior
  before do
    allow(Rubyagents::UI).to receive(:welcome).and_call_original
    allow(Rubyagents::UI).to receive(:step_header).and_call_original
    allow(Rubyagents::UI).to receive(:thought).and_call_original
    allow(Rubyagents::UI).to receive(:code).and_call_original
    allow(Rubyagents::UI).to receive(:observation).and_call_original
    allow(Rubyagents::UI).to receive(:error).and_call_original
    allow(Rubyagents::UI).to receive(:step_metrics).and_call_original
    allow(Rubyagents::UI).to receive(:run_summary).and_call_original
    allow(Rubyagents::UI).to receive(:final_answer).and_call_original
    allow(Rubyagents::UI).to receive(:spinner).and_call_original
  end

  describe "CodeAgent" do
    it "solves a simple math problem" do
      agent = Rubyagents::CodeAgent.new(model: "ollama/qwen2.5:3b", max_steps: 5)
      result = agent.run("What is 2 + 2? Reply with just the number.", return_full_result: true)
      expect(result).to be_a(Rubyagents::RunResult)
      expect(result.output).to include("4")
    end

    it "returns RunResult with timing and token info" do
      agent = Rubyagents::CodeAgent.new(model: "ollama/qwen2.5:3b", max_steps: 3)
      result = agent.run("What is 3 * 3?", return_full_result: true)
      expect(result.timing).to be > 0
      expect(result.steps).not_to be_empty
    end
  end

  describe "ToolCallingAgent" do
    it "solves a simple task with tool calling" do
      agent = Rubyagents::ToolCallingAgent.new(model: "ollama/qwen2.5:3b", max_steps: 5)
      result = agent.run("What is 2 + 2? Use the final_answer tool with just the number.", return_full_result: true)
      expect(result).to be_a(Rubyagents::RunResult)
      # The agent should eventually answer - may take multiple steps with a small model
      if result.success?
        expect(result.output).to include("4")
      end
    end
  end
end
