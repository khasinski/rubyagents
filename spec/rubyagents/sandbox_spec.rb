# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rubyagents::Sandbox do
  let(:final_answer_tool) { Rubyagents::FinalAnswerTool.new }
  let(:sandbox) { described_class.new(tools: [final_answer_tool], timeout: 5) }

  describe "#execute" do
    it "executes simple Ruby code" do
      result = sandbox.execute("1 + 1")
      expect(result[:result]).to eq(2)
      expect(result[:is_final_answer]).to be false
    end

    it "captures stdout" do
      result = sandbox.execute('puts "hello"')
      expect(result[:output]).to include("hello")
    end

    it "returns error for invalid code" do
      result = sandbox.execute("undefined_method_xyz")
      expect(result[:error]).to include("NameError")
    end

    it "times out on long-running code" do
      sandbox = described_class.new(tools: [final_answer_tool], timeout: 1)
      result = sandbox.execute("sleep 10")
      expect(result[:error]).to include("timed out")
    end

    it "detects FinalAnswerException" do
      result = sandbox.execute('final_answer(answer: "the answer")')
      expect(result[:result]).to eq("the answer")
      expect(result[:is_final_answer]).to be true
    end

    it "captures output before final_answer" do
      result = sandbox.execute(<<~RUBY)
        puts "computing..."
        final_answer(answer: "42")
      RUBY
      expect(result[:output]).to include("computing...")
      expect(result[:result]).to eq("42")
      expect(result[:is_final_answer]).to be true
    end
  end

  describe "tool injection" do
    it "makes tools available as methods" do
      test_tool = Rubyagents.tool(:test_echo, "Echoes input", text: "text") { |text:| "echo: #{text}" }
      sandbox = described_class.new(tools: [final_answer_tool, test_tool], timeout: 5)

      result = sandbox.execute('test_echo(text: "hello")')
      expect(result[:result]).to eq("echo: hello")
    end
  end

  describe "isolation" do
    it "does not affect parent process state" do
      original_stdout = $stdout
      sandbox.execute("$stdout = StringIO.new")
      expect($stdout).to eq(original_stdout)
    end
  end
end
