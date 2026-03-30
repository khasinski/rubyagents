# frozen_string_literal: true

module Gemlings
  # Wraps a RubyLLM::Tool (class or instance) as a Gemlings::Tool.
  def self.tool_from_ruby_llm(tool)
    require "ruby_llm"
    instance = tool.is_a?(Class) ? tool.new : tool

    raise ArgumentError, "Expected a RubyLLM::Tool, got #{instance.class}" unless instance.is_a?(RubyLLM::Tool)

    tool_name = instance.name
    tool_desc = instance.description || ""
    params = instance.parameters || {}

    klass = Class.new(Tool) do
      self.tool_name(tool_name)
      description(tool_desc)

      params.each do |pname, param|
        input pname.to_sym,
              type: (param.type || "string").to_sym,
              description: param.description || "",
              required: param.required != false
      end
    end

    wrapper = klass.new
    wrapper.define_singleton_method(:call) do |**kwargs|
      instance.call(kwargs)
    end
    wrapper
  end

  # Wraps a RubyLLM::Agent (class or instance) as a managed Gemlings agent.
  # The agent can be passed in the `agents:` array of a Gemlings agent.
  def self.agent_from_ruby_llm(agent, name: nil, description: nil)
    require "ruby_llm"

    chat = if agent.is_a?(Class) && agent < RubyLLM::Agent
      agent.chat
    elsif agent.is_a?(RubyLLM::Agent)
      agent.chat
    elsif agent.respond_to?(:ask)
      agent
    else
      raise ArgumentError, "Expected a RubyLLM::Agent class, instance, or RubyLLM::Chat, got #{agent.class}"
    end

    agent_name = name || agent.class.name&.split("::")&.last&.downcase || "ruby_llm_agent"
    agent_desc = description || "A RubyLLM agent"

    RubyLLMAgentWrapper.new(chat, name: agent_name, description: agent_desc)
  end

  # Minimal agent-like wrapper around a RubyLLM::Chat so it can be used
  # with Gemlings::ManagedAgentTool.
  class RubyLLMAgentWrapper
    attr_reader :name, :description

    def initialize(chat, name:, description:)
      @chat = chat
      @name = name
      @description = description
    end

    def run(task)
      response = @chat.ask(task)
      response.content
    end
  end
end
