# frozen_string_literal: true

module Rubyagents
  ActionStep = Data.define(:step_number, :thought, :code, :tool_calls, :observation, :error, :duration, :token_usage) do
    def initialize(step_number:, thought:, code: nil, tool_calls: nil, observation: nil, error: nil,
                   duration: 0.0, token_usage: nil)
      super
    end
  end

  PlanningStep = Data.define(:plan, :duration, :token_usage)
  UserMessage = Data.define(:content)

  class Memory
    attr_reader :system_prompt, :task, :steps, :total_tokens, :total_duration

    def initialize(system_prompt:, task:)
      @system_prompt = system_prompt
      @task = task
      @steps = []
      @total_tokens = TokenUsage.new(input_tokens: 0, output_tokens: 0)
      @total_duration = 0.0
    end

    def add_step(thought:, code: nil, tool_calls: nil, observation: nil, error: nil,
                 duration: 0.0, token_usage: nil)
      step = ActionStep.new(
        step_number: action_steps.size + 1,
        thought: thought,
        code: code,
        tool_calls: tool_calls,
        observation: observation,
        error: error,
        duration: duration,
        token_usage: token_usage
      )
      record_step(step, duration, token_usage)
    end

    def add_plan(plan:, duration: 0.0, token_usage: nil)
      step = PlanningStep.new(plan: plan, duration: duration, token_usage: token_usage)
      record_step(step, duration, token_usage)
    end

    def add_user_message(message)
      @steps << UserMessage.new(content: message)
    end

    def action_steps
      @steps.select { |s| s.is_a?(ActionStep) }
    end

    def progress_summary
      completed = action_steps
      return "No steps completed yet." if completed.empty?

      lines = ["Steps completed so far:"]
      completed.each do |step|
        status = step.error ? "failed" : "done"
        summary = step.thought || step.observation || "no details"
        lines << "  #{step.step_number}. [#{status}] #{summary.to_s[0, 100]}"
      end
      lines.join("\n")
    end

    def to_messages
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: task }
      ]

      steps.each do |step|
        case step
        when UserMessage
          messages << { role: "user", content: step.content }
        when PlanningStep
          messages << { role: "assistant", content: "Plan:\n#{step.plan}" }
          messages << { role: "user", content: "Now proceed and carry out this plan." }
        when ActionStep
          assistant_msg = build_assistant_message(step)
          messages << assistant_msg if assistant_msg

          if step.observation
            messages << { role: "user", content: "Observation: #{step.observation}" }
          elsif step.error
            messages << {
              role: "user",
              content: "Error: #{step.error}\nNow let's retry: take care not to repeat previous errors! " \
                       "If you have retried several times, try a completely different approach."
            }
          end
        end
      end

      messages.each { |m| m[:content] = sanitize_utf8(m[:content]) if m[:content] }
    end

    def last_step
      @steps.last
    end

    def return_full_code
      action_steps.filter_map(&:code).join("\n\n")
    end

    private

    def build_assistant_message(step)
      if step.tool_calls
        # For tool calling agents: include content and tool_calls in message
        msg = { role: "assistant" }
        msg[:content] = step.thought if step.thought
        msg[:tool_calls] = step.tool_calls
        msg
      elsif step.thought || step.code
        assistant_content = +""
        assistant_content << "Thought: #{step.thought}\n" if step.thought
        assistant_content << "Code:\n```ruby\n#{step.code}\n```\n" if step.code
        { role: "assistant", content: assistant_content } unless assistant_content.empty?
      end
    end

    def record_step(step, duration, token_usage)
      @steps << step
      @total_duration += duration if duration
      @total_tokens = @total_tokens + token_usage if token_usage
      step
    end

    def sanitize_utf8(str)
      return str unless str.is_a?(String)
      str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
end
