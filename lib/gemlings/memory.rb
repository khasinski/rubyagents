# frozen_string_literal: true

module Gemlings
  ActionStep = Data.define(:step_number, :thought, :code, :tool_calls, :observation, :error, :duration, :token_usage) do
    def initialize(step_number:, thought:, code: nil, tool_calls: nil, observation: nil, error: nil,
                   duration: 0.0, token_usage: nil)
      super
    end

    def to_h
      h = { type: "action", step_number: step_number, thought: thought, duration: duration }
      h[:code] = code if code
      h[:tool_calls] = tool_calls.map(&:to_h) if tool_calls
      h[:observation] = observation if observation
      h[:error] = error if error
      h[:token_usage] = token_usage.to_h if token_usage
      h
    end
  end

  PlanningStep = Data.define(:plan, :duration, :token_usage) do
    def to_h
      h = { type: "planning", plan: plan, duration: duration }
      h[:token_usage] = token_usage.to_h if token_usage
      h
    end
  end

  UserMessage = Data.define(:content) do
    def to_h
      { type: "user_message", content: content }
    end
  end

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
            if step.tool_calls&.any?
              # Some LLM APIs (e.g. Anthropic) require that every tool_use block in an
              # assistant message is immediately followed by a tool_result block in the
              # next user message — a plain text "Observation:" message is rejected.
              # Build a structured tool_result entry for each tool call in this step.
              tool_results = step.tool_calls.map do |tc|
                { type: "tool_result", tool_use_id: tc.id, content: step.observation }
              end
              messages << { role: "user", content: tool_results }
            else
              messages << { role: "user", content: "Observation: #{step.observation}" }
            end
          elsif step.error
            messages << {
              role: "user",
              content: "Error: #{step.error}\nNow let's retry: take care not to repeat previous errors! " \
                       "If you have retried several times, try a completely different approach."
            }
          end
        end
      end

      # Some LLM APIs (e.g. Anthropic) reject messages whose string content ends with
      # trailing whitespace. Strip it from every message to avoid API errors.
      messages.each do |m|
        m[:content] = sanitize_utf8(m[:content]) if m[:content].is_a?(String)
        m[:content] = m[:content].rstrip if m[:content].is_a?(String)
      end
    end

    def last_step
      @steps.last
    end

    def return_full_code
      action_steps.filter_map(&:code).join("\n\n")
    end

    def to_h
      {
        system_prompt: system_prompt,
        task: task,
        steps: steps.map(&:to_h),
        total_tokens: total_tokens.to_h,
        total_duration: total_duration
      }
    end

    def to_json(*args)
      require "json"
      to_h.to_json(*args)
    end

    def replay(io: $stdout)
      io.puts UI::Styles.final_answer.render("Task: ") + task.to_s
      io.puts

      steps.each do |step|
        case step
        when ActionStep
          replay_action_step(step, io)
        when PlanningStep
          io.puts UI::Styles.plan_label.render(" Plan ")
          io.puts UI::Styles.plan_box.render(step.plan)
          replay_metrics(step, io)
        when UserMessage
          io.puts UI::Styles.label.render("User: ") + step.content.to_s
          io.puts
        end
      end

      count = action_steps.size
      parts = ["#{count} #{count == 1 ? "step" : "steps"}", format("%.1fs total", total_duration)]
      parts << total_tokens.to_s if total_tokens.total_tokens > 0
      io.puts UI::Styles.dim.render(parts.join(" | "))
    end

    private

    def replay_action_step(step, io)
      if step.thought
        io.puts UI::Styles.label.render("Thought: ") + step.thought
      end

      if step.code
        io.puts
        highlighted = rouge_formatter.format(rouge_lexer.lex(step.code))
        highlighted.each_line { |line| io.puts "  #{line.rstrip}" }
        io.puts
      end

      if step.tool_calls
        step.tool_calls.each do |tc|
          args = tc.function.arguments.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
          io.puts UI::Styles.label.render("Tool: ") + "#{tc.function.name}(#{args})"
        end
      end

      if step.observation
        io.puts UI::Styles.label.render("Result: ") + step.observation.to_s[0, 200]
      end

      if step.error
        io.puts UI::Styles.error.render("Error: ") + step.error
      end

      replay_metrics(step, io)
    end

    def replay_metrics(step, io)
      parts = []
      parts << format("%.1fs", step.duration) if step.duration > 0
      parts << step.token_usage.to_s if step.token_usage
      io.puts UI::Styles.dim.render(parts.join(" | ")) unless parts.empty?
      io.puts
    end

    def rouge_lexer
      @rouge_lexer ||= Rouge::Lexers::Ruby.new
    end

    def rouge_formatter
      @rouge_formatter ||= Rouge::Formatters::Terminal256.new(Rouge::Themes::Monokai.new)
    end

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
