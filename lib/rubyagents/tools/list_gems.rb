# frozen_string_literal: true

module Rubyagents
  class ListGems < Tool
    tool_name "list_gems"
    description "Lists Ruby gems available in the current environment that you can require and use in your code"
    output_type :string

    def call(**_kwargs)
      specs = Gem::Specification.sort_by(&:name)
      lines = specs.map { |s| "#{s.name} (#{s.version}) - #{s.summary&.slice(0, 80)}" }
      lines.join("\n")
    end
  end
end
