# frozen_string_literal: true

module Rubyagents
  class ToolCallingAgent < Agent
    private

    def system_prompt
      prompt = if @prompt_templates.system_prompt
        tool_descriptions = tools.map { |t| t.class.to_prompt }.join("\n\n")
        @prompt_templates.system_prompt.gsub("{{tool_descriptions}}", tool_descriptions)
      else
        Prompt.tool_calling_agent_system(tools: tools)
      end
      prompt = "#{prompt}\n\n#{@instructions}" if @instructions
      prompt
    end

    def generate_response(messages, &on_stream)
      tool_schemas = tools.map { |t| t.class.to_schema }
      spin = on_stream ? nil : UI.spinner("Thinking...")
      spin&.start
      response = @model.generate(messages, tools: tool_schemas, &on_stream)
      spin&.stop
      response
    end

    def parse_response(response)
      [response.content, response.tool_calls]
    end

    def run_action(thought, tool_calls, response, llm_duration)
      return nil unless tool_calls&.any?

      results = []
      final_answer_value = nil

      tool_calls.each do |tc|
        tool_name = tc.function.name
        arguments = tc.function.arguments

        UI.code("#{tool_name}(#{arguments.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")})")

        if tool_name == "final_answer"
          final_answer_value = arguments[:answer] || arguments["answer"]
          results << "Final answer: #{final_answer_value}"
          next
        end

        tool = @tool_map[tool_name]
        unless tool
          error_msg = "Unknown tool: #{tool_name}"
          UI.error(error_msg)
          results << "Error: #{error_msg}"
          next
        end

        begin
          # Convert string keys to symbols for tool call
          sym_args = arguments.transform_keys(&:to_sym)
          result = tool.call(**sym_args)
          UI.observation(result.to_s)
          results << result.to_s
        rescue => e
          UI.error("#{e.class}: #{e.message}")
          results << "Error: #{e.message}"
        end
      end

      total_output = results.join("\n")
      UI.step_metrics(duration: llm_duration, token_usage: response.token_usage)

      step = memory.add_step(
        thought: thought,
        tool_calls: tool_calls,
        observation: total_output,
        duration: llm_duration,
        token_usage: response.token_usage
      )
      notify_callbacks(step)

      final_answer_value
    end
  end
end
