# frozen_string_literal: true

module Rubyagents
  class Agent
    attr_reader :name, :description, :model, :tools, :max_steps, :memory, :planning_interval, :step_callbacks, :callbacks

    def initialize(model:, tools: [], agents: [], name: nil, description: nil,
                   max_steps: 10, planning_interval: nil, step_callbacks: [],
                   callbacks: [], final_answer_checks: [], prompt_templates: nil,
                   instructions: nil, output_type: nil)
      @name = name
      @description = description
      @model = model.is_a?(String) ? Model.for(model) : model
      @tools = build_tools(tools, agents)
      @max_steps = max_steps
      @planning_interval = planning_interval
      @step_callbacks = step_callbacks
      @callbacks = Array(callbacks)
      @final_answer_checks = final_answer_checks
      @prompt_templates = prompt_templates || PromptTemplates.new
      @instructions = instructions
      @output_type = output_type
      @memory = nil
      @interrupt_switch = false
      @step_number = 0
      @final_answer_value = nil
      @tool_map = @tools.each_with_object({}) { |t, h| h[t.class.tool_name] = t }
    end

    def run(task, reset: true, return_full_result: false, &on_stream)
      @interrupt_switch = false

      if reset || @memory.nil?
        @memory = Memory.new(system_prompt: system_prompt, task: task)
      else
        memory.add_user_message(task)
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      notify(:on_run_start, task: task)

      (1..max_steps).each do |step_number|
        raise InterruptError, "Agent interrupted" if @interrupt_switch

        notify(:on_step_start, step_number: step_number)
        maybe_plan(step_number)

        # Call LLM with timing
        llm_duration, response = timed { generate_response(memory.to_messages, &on_stream) }

        # Parse response
        thought, action = parse_response(response)
        UI.thought(thought) if thought

        # Check for final answer or execute
        if action
          result = run_action(thought, action, response, llm_duration)
          if result
            error_msg = validate_final_answer(result)
            error_msg ||= validate_output_type(result)
            if error_msg
              memory.add_user_message(error_msg)
              next
            end
            total_timing = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
            built = build_result(result, total_timing, return_full_result)
            notify(:on_run_end, result: built)
            return built
          end
        else
          UI.step_metrics(duration: llm_duration, token_usage: response.token_usage)
          step = memory.add_step(thought: thought || response.content, code: nil, observation: nil,
                                 duration: llm_duration, token_usage: response.token_usage)
          notify_callbacks(step)
        end
      end

      # Max steps reached
      UI.run_summary(
        total_steps: memory.action_steps.size,
        total_duration: memory.total_duration,
        total_tokens: memory.total_tokens
      )
      UI.error("Max steps (#{max_steps}) reached without a final answer")
      notify(:on_error, error: MaxStepsError.new("Max steps (#{max_steps}) reached"))

      total_timing = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      output = memory.last_step&.observation
      result = RunResult.new(
        output: output,
        state: "max_steps",
        steps: memory.action_steps,
        token_usage: memory.total_tokens,
        timing: total_timing
      )
      notify(:on_run_end, result: return_full_result ? result : output)
      return_full_result ? result : output
    end

    # --- Step-by-step execution ---

    def step(task_or_message = nil)
      if @memory.nil?
        raise ArgumentError, "task required on first call" unless task_or_message
        @memory = Memory.new(system_prompt: system_prompt, task: task_or_message)
        @step_number = 0
        @interrupt_switch = false
        @final_answer_value = nil
      elsif task_or_message
        memory.add_user_message(task_or_message)
      end

      @step_number += 1
      raise MaxStepsError, "Max steps (#{max_steps}) reached" if @step_number > max_steps
      raise InterruptError, "Agent interrupted" if @interrupt_switch

      maybe_plan(@step_number)

      llm_duration, response = timed { generate_response(memory.to_messages) }
      thought, action = parse_response(response)

      if action
        result = run_action(thought, action, response, llm_duration)
        if result
          error_msg = validate_final_answer(result)
          error_msg ||= validate_output_type(result)
          if error_msg
            memory.add_user_message(error_msg)
          else
            @final_answer_value = result
          end
        end
      else
        memory.add_step(thought: thought || response.content,
                        duration: llm_duration, token_usage: response.token_usage)
      end

      memory.last_step
    end

    def done? = !@final_answer_value.nil?

    def final_answer_value = @final_answer_value

    def reset!
      @memory = nil
      @step_number = 0
      @final_answer_value = nil
      @interrupt_switch = false
    end

    def interrupt
      @interrupt_switch = true
    end

    private

    def system_prompt
      raise NotImplementedError
    end

    def generate_response(messages, &on_stream)
      spin = on_stream ? nil : UI.spinner("Thinking...")
      spin&.start
      response = @model.generate(messages, &on_stream)
      spin&.stop
      response
    end

    def parse_response(response)
      raise NotImplementedError
    end

    def execute(action)
      raise NotImplementedError
    end

    def run_action(thought, action, response, llm_duration)
      raise NotImplementedError
    end

    def maybe_plan(step_number)
      return unless planning_interval
      if step_number == 1
        run_planning_step(initial: true)
      elsif (step_number % planning_interval) == 1
        run_planning_step(initial: false)
      end
    end

    def run_planning_step(initial: true)
      spin = UI.spinner("Planning...")
      spin.start
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      planning_messages = memory.to_messages
      if initial
        plan_prompt = @prompt_templates.planning_initial || Prompt.initial_plan
        planning_messages[0] = { role: "system", content: plan_prompt }
      else
        plan_prompt = @prompt_templates.planning_update || Prompt.update_plan(progress_summary: memory.progress_summary)
        planning_messages[0] = { role: "system", content: plan_prompt }
      end

      response = @model.generate(planning_messages)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      spin.stop

      UI.plan(response.content)
      UI.step_metrics(duration: duration, token_usage: response.token_usage)
      memory.add_plan(plan: response.content, duration: duration, token_usage: response.token_usage)
    end

    def validate_final_answer(answer)
      @final_answer_checks.each_with_index do |check, i|
        unless check.call(answer, memory)
          return "Final answer rejected by check ##{i + 1}. Please try a different answer."
        end
      end
      nil
    end

    def validate_output_type(answer)
      return nil unless @output_type
      case @output_type
      when Hash
        require "json-schema"
        errors = JSON::Validator.fully_validate(@output_type, answer)
        errors.empty? ? nil : "Output validation failed: #{errors.join("; ")}"
      when Proc
        @output_type.call(answer) ? nil : "Output validation failed: custom validator returned falsy"
      end
    end

    def build_tools(tool_classes, agents)
      instances = [FinalAnswerTool.new]

      tool_classes.each do |klass|
        instances << (klass.is_a?(Tool) ? klass : klass.new)
      end

      agents.each do |agent|
        instances << ManagedAgentTool.for(agent)
      end

      instances
    end

    def build_result(output, timing, return_full_result)
      UI.run_summary(
        total_steps: memory.action_steps.size,
        total_duration: memory.total_duration,
        total_tokens: memory.total_tokens
      )
      UI.final_answer(output)

      result = RunResult.new(
        output: output,
        state: "success",
        steps: memory.action_steps,
        token_usage: memory.total_tokens,
        timing: timing
      )
      return_full_result ? result : output
    end

    def notify_callbacks(step)
      @step_callbacks.each { |cb| cb.call(step, agent: self) }
      notify(:on_step_end, step: step)
    end

    def notify(event, **payload)
      @callbacks.each do |cb|
        cb.send(event, **payload, agent: self) if cb.respond_to?(event)
      end
    end

    def format_output(result)
      parts = []
      parts << result[:output] unless result[:output].to_s.empty?
      parts << result[:result].inspect unless result[:result].nil?
      parts.join("\n")
    end

    def timed
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      [duration, result]
    end
  end

  class ManagedAgentTool < Tool
    tool_name "call_agent"
    description "Delegates a task to a managed agent"
    input :task, type: :string, description: "Task to delegate"
    output_type :string

    # Factory that creates an anonymous subclass per agent instance
    def self.for(agent)
      klass = Class.new(self) do
        tool_name(agent.name || "agent")
        description(agent.description || "A managed agent")
      end
      klass.new(agent)
    end

    def initialize(agent)
      @agent = agent
    end

    def call(task:, **_kwargs)
      @agent.run(task)
    end
  end
end
