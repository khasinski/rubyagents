# frozen_string_literal: true

module Rubyagents
  class Callback
    def on_run_start(task:, agent:) = nil
    def on_step_start(step_number:, agent:) = nil
    def on_step_end(step:, agent:) = nil
    def on_tool_call(tool_name:, arguments:, agent:) = nil
    def on_error(error:, agent:) = nil
    def on_run_end(result:, agent:) = nil
  end
end
