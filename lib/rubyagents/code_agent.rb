# frozen_string_literal: true

module Rubyagents
  class CodeAgent < Agent
    CODE_BLOCK_RE = /```ruby\s*\n(.*?)```/m

    def initialize(model:, tools: [], agents: [], name: nil, description: nil,
                   max_steps: 10, timeout: 30, planning_interval: nil, step_callbacks: [],
                   final_answer_checks: [], prompt_templates: nil, instructions: nil,
                   output_type: nil)
      super(model: model, tools: tools, agents: agents, name: name, description: description,
            max_steps: max_steps, planning_interval: planning_interval, step_callbacks: step_callbacks,
            final_answer_checks: final_answer_checks, prompt_templates: prompt_templates,
            instructions: instructions, output_type: output_type)
      @timeout = timeout
    end

    private

    def system_prompt
      prompt = if @prompt_templates.system_prompt
        tool_descriptions = tools.map { |t| t.class.to_prompt }.join("\n\n")
        @prompt_templates.system_prompt.gsub("{{tool_descriptions}}", tool_descriptions)
      else
        Prompt.code_agent_system(tools: tools)
      end
      prompt = "#{prompt}\n\n#{@instructions}" if @instructions
      prompt
    end

    def parse_response(response)
      content = response.content

      thought = nil
      if content =~ /Thought:\s*(.*?)(?=Code:|```ruby)/m
        thought = $1.strip
      elsif content =~ /Thought:\s*(.*)/m
        thought = $1.strip
      end

      code = nil
      if content =~ CODE_BLOCK_RE
        code = $1.strip
      end

      [thought, code]
    end

    def run_action(thought, code, response, llm_duration)
      UI.code(code)
      exec_duration, result = timed { execute(code) }
      total_duration = llm_duration + exec_duration

      if result[:error]
        UI.error(result[:error])
        UI.step_metrics(duration: total_duration, token_usage: response.token_usage)
        step = memory.add_step(thought: thought, code: code, error: result[:error],
                               duration: total_duration, token_usage: response.token_usage)
        notify_callbacks(step)
        nil
      else
        output = format_output(result)
        UI.observation(output)
        UI.step_metrics(duration: total_duration, token_usage: response.token_usage)

        step = memory.add_step(thought: thought, code: code, observation: output,
                               duration: total_duration, token_usage: response.token_usage)
        notify_callbacks(step)

        result[:is_final_answer] ? result[:result] : nil
      end
    end

    def execute(code)
      spin = UI.spinner("Executing code...")
      spin.start
      sandbox = Sandbox.new(tools: tools, timeout: @timeout)
      result = sandbox.execute(code)
      spin.stop
      result
    end
  end
end
