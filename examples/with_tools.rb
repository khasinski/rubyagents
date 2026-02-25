#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/rubyagents"
require_relative "../lib/rubyagents/tools/web_search"

agent = Rubyagents::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  tools: [Rubyagents::WebSearch]
)

agent.run("What year was Ruby created and who created it?")
