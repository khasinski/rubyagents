# frozen_string_literal: true

require "spec_helper"

RSpec.describe "structured output validation" do
  let(:model) { instance_double(Rubyagents::Model) }

  def tool_calling_response(answer)
    Rubyagents::ChatMessage.new(
      role: "assistant",
      content: "Here's the answer.",
      token_usage: Rubyagents::TokenUsage.new(input_tokens: 10, output_tokens: 20),
      tool_calls: [
        Rubyagents::ToolCall.new(
          id: "call_1",
          function: Rubyagents::ToolCallFunction.new(name: "final_answer", arguments: { "answer" => answer })
        )
      ]
    )
  end

  describe "nil output_type (default)" do
    it "accepts any answer" do
      allow(model).to receive(:generate).and_return(tool_calling_response("anything"))
      agent = Rubyagents::ToolCallingAgent.new(model: model)
      expect(agent.run("Test")).to eq("anything")
    end
  end

  describe "Proc output_type" do
    it "accepts answer when proc returns truthy" do
      allow(model).to receive(:generate).and_return(tool_calling_response("42"))

      validator = ->(answer) { answer == "42" }
      agent = Rubyagents::ToolCallingAgent.new(model: model, output_type: validator)
      expect(agent.run("Test")).to eq("42")
    end

    it "rejects answer when proc returns falsy and retries" do
      responses = [
        tool_calling_response("wrong"),
        tool_calling_response("42")
      ]
      allow(model).to receive(:generate).and_return(*responses)

      validator = ->(answer) { answer == "42" }
      agent = Rubyagents::ToolCallingAgent.new(model: model, output_type: validator, max_steps: 5)
      expect(agent.run("Test")).to eq("42")
      expect(model).to have_received(:generate).twice
    end
  end

  describe "Hash output_type (JSON Schema)" do
    let(:schema) do
      {
        "type" => "object",
        "required" => ["name"],
        "properties" => {
          "name" => { "type" => "string" }
        }
      }
    end

    it "accepts valid JSON matching schema" do
      valid_data = { "name" => "Alice" }
      allow(model).to receive(:generate).and_return(tool_calling_response(valid_data))

      agent = Rubyagents::ToolCallingAgent.new(model: model, output_type: schema)
      expect(agent.run("Test")).to eq(valid_data)
    end

    it "rejects invalid data and retries" do
      invalid_data = { "age" => 30 }
      valid_data = { "name" => "Bob" }
      responses = [
        tool_calling_response(invalid_data),
        tool_calling_response(valid_data)
      ]
      allow(model).to receive(:generate).and_return(*responses)

      agent = Rubyagents::ToolCallingAgent.new(model: model, output_type: schema, max_steps: 5)
      expect(agent.run("Test")).to eq(valid_data)
      expect(model).to have_received(:generate).twice
    end
  end

  describe "combined with final_answer_checks" do
    it "runs both validations" do
      responses = [
        tool_calling_response("bad"),  # fails final_answer_check
        tool_calling_response("42"),   # passes both
      ]
      allow(model).to receive(:generate).and_return(*responses)

      check = ->(answer, _mem) { answer != "bad" }
      validator = ->(answer) { answer == "42" }
      agent = Rubyagents::ToolCallingAgent.new(
        model: model,
        final_answer_checks: [check],
        output_type: validator,
        max_steps: 5
      )
      expect(agent.run("Test")).to eq("42")
    end
  end
end
