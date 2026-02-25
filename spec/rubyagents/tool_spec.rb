# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rubyagents::Tool do
  describe "DSL" do
    let(:tool_class) do
      Class.new(described_class) do
        tool_name "test_tool"
        description "A test tool"
        input :name, type: :string, description: "The name"
        input :count, type: :integer, description: "A count", required: false
        output_type :string

        def call(name:, count: 1)
          "#{name} x#{count}"
        end
      end
    end

    it "sets tool_name" do
      expect(tool_class.tool_name).to eq("test_tool")
    end

    it "sets description" do
      expect(tool_class.description).to eq("A test tool")
    end

    it "tracks inputs" do
      expect(tool_class.inputs).to include(:name, :count)
      expect(tool_class.inputs[:name][:required]).to be true
      expect(tool_class.inputs[:count][:required]).to be false
    end

    it "sets output_type" do
      expect(tool_class.output_type).to eq(:string)
    end

    it "calls the tool" do
      expect(tool_class.new.call(name: "hello")).to eq("hello x1")
      expect(tool_class.new.call(name: "hello", count: 3)).to eq("hello x3")
    end
  end

  describe ".to_schema" do
    let(:tool_class) do
      Class.new(described_class) do
        tool_name "schema_tool"
        description "Schema test"
        input :query, type: :string, description: "Search query"
      end
    end

    it "generates correct JSON schema" do
      schema = tool_class.to_schema
      expect(schema[:name]).to eq("schema_tool")
      expect(schema[:description]).to eq("Schema test")
      expect(schema[:parameters][:type]).to eq("object")
      expect(schema[:parameters][:properties][:query][:type]).to eq("string")
      expect(schema[:parameters][:required]).to eq(["query"])
    end
  end

  describe ".to_prompt" do
    let(:tool_class) do
      Class.new(described_class) do
        tool_name "prompt_tool"
        description "Prompt test"
        input :text, type: :string, description: "The text"
      end
    end

    it "generates human-readable prompt" do
      prompt = tool_class.to_prompt
      expect(prompt).to include("prompt_tool")
      expect(prompt).to include("Prompt test")
      expect(prompt).to include("text (string)")
    end
  end

  describe "Rubyagents.tool block shorthand" do
    let(:tool) do
      Rubyagents.tool(:greet, "Greets a person", name: "The person's name") do |name:|
        "Hello, #{name}!"
      end
    end

    it "creates a callable tool instance" do
      expect(tool.class.tool_name).to eq("greet")
      expect(tool.class.description).to eq("Greets a person")
      expect(tool.call(name: "World")).to eq("Hello, World!")
    end
  end

  describe Rubyagents::ManagedAgentTool do
    describe ".for" do
      it "creates an anonymous subclass per agent with isolated class state" do
        agent1 = instance_double(Rubyagents::Agent, name: "agent_one", description: "First agent")
        agent2 = instance_double(Rubyagents::Agent, name: "agent_two", description: "Second agent")

        tool1 = described_class.for(agent1)
        tool2 = described_class.for(agent2)

        expect(tool1.class.tool_name).to eq("agent_one")
        expect(tool2.class.tool_name).to eq("agent_two")
        expect(tool1.class).not_to eq(tool2.class)
      end
    end
  end

  describe Rubyagents::FinalAnswerTool do
    it "returns the answer" do
      tool = described_class.new
      expect(tool.call(answer: "42")).to eq("42")
    end
  end
end
