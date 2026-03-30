# frozen_string_literal: true

require "spec_helper"
require "ruby_llm"

RSpec.describe "RubyLLM interop" do
  describe "Gemlings.tool_from_ruby_llm" do
    it "wraps a RubyLLM::Tool class" do
      ruby_llm_tool = Class.new(RubyLLM::Tool) do
        description "Echoes input"
        param :message, type: :string, desc: "The message"

        def execute(message:)
          "echo: #{message}"
        end
      end

      tool = Gemlings.tool_from_ruby_llm(ruby_llm_tool)

      expect(tool).to be_a(Gemlings::Tool)
      expect(tool.class.description).to eq("Echoes input")
      expect(tool.class.inputs).to have_key(:message)
      expect(tool.call(message: "hello")).to eq("echo: hello")
    end

    it "wraps a RubyLLM::Tool instance" do
      ruby_llm_tool = Class.new(RubyLLM::Tool) do
        description "Adds numbers"
        param :a, type: :integer, desc: "First number"
        param :b, type: :integer, desc: "Second number"

        def execute(a:, b:)
          a + b
        end
      end

      tool = Gemlings.tool_from_ruby_llm(ruby_llm_tool.new)

      expect(tool.call(a: 3, b: 5)).to eq(8)
    end

    it "preserves parameter metadata" do
      ruby_llm_tool = Class.new(RubyLLM::Tool) do
        description "Test"
        param :required_param, type: :string, desc: "Required", required: true
        param :optional_param, type: :integer, desc: "Optional", required: false

        def execute(**kwargs) = kwargs
      end

      tool = Gemlings.tool_from_ruby_llm(ruby_llm_tool)
      inputs = tool.class.inputs

      expect(inputs[:required_param][:required]).to be true
      expect(inputs[:optional_param][:required]).to be false
      expect(inputs[:required_param][:type]).to eq(:string)
      expect(inputs[:optional_param][:type]).to eq(:integer)
    end

    it "raises for non-RubyLLM::Tool" do
      expect { Gemlings.tool_from_ruby_llm("not a tool") }
        .to raise_error(ArgumentError, /Expected a RubyLLM::Tool/)
    end

    it "generates correct schema for use in agents" do
      ruby_llm_tool = Class.new(RubyLLM::Tool) do
        description "Gets weather"
        param :city, type: :string, desc: "City name"

        def execute(city:) = "sunny in #{city}"
      end

      tool = Gemlings.tool_from_ruby_llm(ruby_llm_tool)
      schema = tool.class.to_schema

      expect(schema[:name]).to be_a(String)
      expect(schema[:description]).to eq("Gets weather")
      expect(schema[:parameters][:properties]).to have_key(:city)
    end
  end

  describe "Gemlings.agent_from_ruby_llm" do
    it "wraps a RubyLLM::Chat as a managed agent" do
      chat = instance_double(RubyLLM::Chat)
      response = double("response", content: "The answer is 42")
      allow(chat).to receive(:ask).with("What is 6*7?").and_return(response)

      wrapper = Gemlings.agent_from_ruby_llm(chat, name: "calculator", description: "Does math")

      expect(wrapper.name).to eq("calculator")
      expect(wrapper.description).to eq("Does math")
      expect(wrapper.run("What is 6*7?")).to eq("The answer is 42")
    end

    it "raises for invalid input" do
      expect { Gemlings.agent_from_ruby_llm("not an agent") }
        .to raise_error(ArgumentError, /Expected a RubyLLM::Agent/)
    end
  end
end
