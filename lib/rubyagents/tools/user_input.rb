# frozen_string_literal: true

module Rubyagents
  class UserInput < Tool
    tool_name "user_input"
    description "Asks the user a question and returns their response. Use this when you need clarification."
    input :question, type: :string, description: "The question to ask the user"
    output_type :string

    def call(question:)
      $stderr.print "\n#{question}\n> "
      response = $stdin.gets&.strip
      response || ""
    end
  end
end
