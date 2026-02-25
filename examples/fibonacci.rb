#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/rubyagents"

agent = Rubyagents::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514")
agent.run("What is the 118th Fibonacci number?")
