# frozen_string_literal: true

module Rubyagents
  TokenUsage = Data.define(:input_tokens, :output_tokens) do
    def total_tokens = input_tokens + output_tokens

    def +(other)
      TokenUsage.new(
        input_tokens: input_tokens + other.input_tokens,
        output_tokens: output_tokens + other.output_tokens
      )
    end

    def to_s
      "#{total_tokens} tokens (#{input_tokens} in / #{output_tokens} out)"
    end
  end

  ToolCallFunction = Data.define(:name, :arguments)
  ToolCall = Data.define(:id, :function)

  ChatMessage = Data.define(:role, :content, :token_usage, :tool_calls) do
    def initialize(role:, content:, token_usage: nil, tool_calls: nil)
      super
    end
  end

  RunResult = Data.define(:output, :state, :steps, :token_usage, :timing) do
    def initialize(output:, state:, steps: [], token_usage: nil, timing: nil)
      super
    end

    def success? = state == "success"
  end

  class Model
    @registry = {}

    class << self
      attr_reader :registry

      def register(prefix, klass)
        @registry[prefix] = klass
      end

      def for(model_id)
        prefix, model_name = model_id.split("/", 2)
        raise Error, "Invalid model ID format: #{model_id}. Use 'provider/model-name'" unless model_name

        adapter_class = @registry[prefix]
        raise Error, "Unknown model provider: #{prefix}. Available: #{@registry.keys.join(", ")}" unless adapter_class

        adapter_class.new(model_name)
      end
    end

    attr_reader :model_name

    def initialize(model_name)
      @model_name = model_name
    end

    def generate(messages, tools: nil, &on_stream)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end
  end
end
