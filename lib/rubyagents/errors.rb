# frozen_string_literal: true

module Rubyagents
  class Error < StandardError; end
  class AgentError < Error; end
  class ParsingError < AgentError; end
  class ExecutionError < AgentError; end
  class GenerationError < AgentError; end
  class MaxStepsError < AgentError; end
  class InterruptError < AgentError; end

  # Inherits Exception (not StandardError) so agent-generated `rescue => e` won't catch it
  class FinalAnswerException < Exception # rubocop:disable Lint/InheritException
    attr_reader :value

    def initialize(value)
      @value = value
      super("Final answer reached")
    end
  end
end
