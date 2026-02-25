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

    def to_h
      { input_tokens: input_tokens, output_tokens: output_tokens }
    end
  end

  ToolCallFunction = Data.define(:name, :arguments) do
    def to_h
      { name: name, arguments: arguments }
    end
  end

  ToolCall = Data.define(:id, :function) do
    def to_h
      { id: id, function: function.to_h }
    end
  end

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

    def to_h
      {
        output: output,
        state: state,
        steps: steps.map(&:to_h),
        token_usage: token_usage&.to_h,
        timing: timing
      }
    end

    def to_json(*args)
      require "json"
      to_h.to_json(*args)
    end
  end

  class Model
    @registry = {}

    class << self
      attr_reader :registry

      def register(prefix, klass)
        @registry[prefix] = klass
      end

      def for(model_id)
        if model_id.include?("/")
          prefix, model_name = model_id.split("/", 2)
          adapter_class = @registry[prefix]
          if adapter_class
            adapter_class.new(model_name)
          else
            Models::RubyLLMAdapter.new(model_name, provider: prefix)
          end
        else
          Models::RubyLLMAdapter.new(model_id)
        end
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
