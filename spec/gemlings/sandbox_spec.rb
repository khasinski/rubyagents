# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gemlings::Sandbox do
  let(:final_answer_tool) { Gemlings::FinalAnswerTool.new }
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
      test_tool = Gemlings.tool(:test_echo, "Echoes input", text: "text") { |text:| "echo: #{text}" }
      sandbox = described_class.new(tools: [final_answer_tool, test_tool], timeout: 5)

      result = sandbox.execute('test_echo(text: "hello")')
      expect(result[:result]).to eq("echo: hello")
    end
  end

  describe "isolation" do
    it "does not affect parent process state", skip: (RUBY_ENGINE == "jruby" ? "JRuby uses thread-based executor without process isolation" : false) do
      original_stdout = $stdout
      sandbox.execute("$stdout = StringIO.new")
      expect($stdout).to eq(original_stdout)
    end
  end

  describe "executor selection" do
    it "returns a default executor for the current platform" do
      default = described_class.default_executor
      expect(%i[fork thread box]).to include(default)
    end

    it "resolves a valid executor" do
      executor = described_class.resolve_executor(described_class.default_executor)
      expect(executor).to be_a(Gemlings::Sandbox::Executor)
    end

    it "raises ArgumentError for unknown executor" do
      expect { described_class.resolve_executor(:banana) }
        .to raise_error(ArgumentError, /Unknown executor.*banana/)
    end

    it "raises Error for unavailable executor" do
      # ForkExecutor is unavailable on JRuby, ThreadExecutor is always available
      if RUBY_ENGINE == "jruby"
        expect { described_class.resolve_executor(:fork) }
          .to raise_error(Gemlings::Error, /not available/)
      else
        # BoxExecutor is unavailable without RUBY_BOX=1 (unless running Ruby 4.0+ with it)
        unless Gemlings::Sandbox::BoxExecutor.available?
          expect { described_class.resolve_executor(:box) }
            .to raise_error(Gemlings::Error, /not available/)
        end
      end
    end

    it "accepts executor option in constructor" do
      default = described_class.default_executor
      sandbox = described_class.new(tools: [final_answer_tool], timeout: 5, executor: described_class.resolve_executor(default))
      result = sandbox.execute("1 + 1")
      expect(result[:result]).to eq(2)
    end
  end
end
