# frozen_string_literal: true

module Rubyagents
  class Tool
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@inputs, {})
      end

      def tool_name(value = nil)
        if value
          @tool_name = value
        else
          @tool_name || name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end
      end
      alias_method :name, :tool_name

      def description(value = nil)
        if value
          @description = value
        else
          @description || ""
        end
      end

      def input(name, type:, description:, required: true)
        @inputs[name] = { type: type, description: description, required: required }
      end

      def inputs
        @inputs ||= {}
      end

      def output_type(value = nil)
        if value
          @output_type = value
        else
          @output_type || :string
        end
      end

      def to_schema
        properties = {}
        required = []

        inputs.each do |param_name, config|
          properties[param_name] = {
            type: config[:type].to_s,
            description: config[:description]
          }
          required << param_name.to_s if config[:required]
        end

        {
          name: tool_name,
          description: description,
          parameters: {
            type: "object",
            properties: properties,
            required: required
          }
        }
      end

      def to_prompt
        lines = ["Tool: #{tool_name}", "Description: #{description}"]

        if inputs.any?
          lines << "Inputs:"
          inputs.each do |param_name, config|
            opt = config[:required] ? "" : " (optional)"
            lines << "  - #{param_name} (#{config[:type]}#{opt}): #{config[:description]}"
          end
        end

        lines << "Output type: #{output_type}"
        lines.join("\n")
      end
    end

    def call(**kwargs)
      raise NotImplementedError, "#{self.class} must implement #call"
    end
  end

  # Built-in tool: signals the final answer
  class FinalAnswerTool < Tool
    tool_name "final_answer"
    description "Returns the final answer to the user's question"
    input :answer, type: :string, description: "The final answer to return"
    output_type :string

    def call(answer:)
      answer
    end
  end

  # Block-based tool shorthand
  # Usage:
  #   greet = Rubyagents.tool(:greet, "Greets a person", name: "The person's name") { |name:| "Hello, #{name}!" }
  def self.tool(tool_name, desc, output: :string, **inputs, &block)
    klass = Class.new(Tool) do
      self.tool_name(tool_name.to_s)
      self.description(desc)

      inputs.each do |param_name, param_desc|
        type, description = if param_desc.is_a?(Hash)
          [param_desc[:type] || :string, param_desc[:description] || param_desc.to_s]
        else
          [:string, param_desc.to_s]
        end
        input param_name, type: type, description: description
      end

      self.output_type(output)

      define_method(:call, &block)
    end

    klass.new
  end
end
