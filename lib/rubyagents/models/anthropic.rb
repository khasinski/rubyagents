# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Rubyagents
  module Models
    class Anthropic < Model
      API_URL = "https://api.anthropic.com/v1/messages"

      def initialize(model_name)
        super
        @api_key = ENV.fetch("ANTHROPIC_API_KEY") {
          raise Error, "ANTHROPIC_API_KEY environment variable is required"
        }
      end

      def generate(messages, tools: nil, &on_stream)
        system_msg = nil
        chat_messages = messages.filter_map do |m|
          if m[:role] == "system"
            system_msg = m[:content]
            nil
          else
            msg = { role: m[:role], content: m[:content] || "" }
            msg
          end
        end

        body = {
          model: model_name,
          max_tokens: 4096,
          messages: chat_messages
        }
        body[:system] = system_msg if system_msg

        if tools&.any?
          body[:tools] = tools.map { |t| format_tool(t) }
        end

        if on_stream
          body[:stream] = true
          stream_request(body, &on_stream)
        else
          response = post(body)
          data = JSON.parse(response.body)

          if data["error"]
            raise Error, "Anthropic API error: #{data["error"]["message"]}"
          end

          parse_response(data)
        end
      end

      private

      def format_tool(schema)
        {
          name: schema[:name],
          description: schema[:description],
          input_schema: schema[:parameters]
        }
      end

      def parse_response(data)
        content = nil
        tool_calls = []

        data["content"]&.each do |block|
          case block["type"]
          when "text"
            content = block["text"]
          when "tool_use"
            tool_calls << ToolCall.new(
              id: block["id"],
              function: ToolCallFunction.new(
                name: block["name"],
                arguments: block["input"] || {}
              )
            )
          end
        end

        usage = parse_usage(data["usage"])
        ChatMessage.new(
          role: "assistant",
          content: content,
          token_usage: usage,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )
      end

      def parse_usage(usage)
        return nil unless usage
        TokenUsage.new(
          input_tokens: usage["input_tokens"] || 0,
          output_tokens: usage["output_tokens"] || 0
        )
      end

      def post(body)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["anthropic-version"] = "2023-06-01"
        request["content-type"] = "application/json"
        request.body = JSON.generate(body)

        http.request(request)
      end

      def stream_request(body, &on_stream)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["x-api-key"] = @api_key
        request["anthropic-version"] = "2023-06-01"
        request["content-type"] = "application/json"
        request.body = JSON.generate(body)

        full_content = +""
        usage = nil
        tool_calls = []
        current_tool = nil

        http.request(request) do |response|
          response.read_body do |chunk|
            chunk.split("\n").each do |line|
              next unless line.start_with?("data: ")
              data = line.sub("data: ", "")
              next if data.strip.empty?

              parsed = JSON.parse(data)

              case parsed["type"]
              when "content_block_start"
                block = parsed["content_block"]
                if block["type"] == "tool_use"
                  current_tool = { "id" => block["id"], "name" => block["name"], "input_json" => +"" }
                end
              when "content_block_delta"
                delta = parsed["delta"]
                if delta["type"] == "text_delta"
                  text = delta["text"]
                  if text
                    full_content << text
                    on_stream.call(text)
                  end
                elsif delta["type"] == "input_json_delta" && current_tool
                  current_tool["input_json"] << (delta["partial_json"] || "")
                end
              when "content_block_stop"
                if current_tool
                  input = current_tool["input_json"].empty? ? {} : JSON.parse(current_tool["input_json"])
                  tool_calls << ToolCall.new(
                    id: current_tool["id"],
                    function: ToolCallFunction.new(
                      name: current_tool["name"],
                      arguments: input
                    )
                  )
                  current_tool = nil
                end
              when "message_delta"
                if (u = parsed.dig("usage"))
                  output_tokens = u["output_tokens"] || 0
                  usage = TokenUsage.new(
                    input_tokens: usage&.input_tokens || 0,
                    output_tokens: output_tokens
                  )
                end
              when "message_start"
                if (u = parsed.dig("message", "usage"))
                  usage = TokenUsage.new(
                    input_tokens: u["input_tokens"] || 0,
                    output_tokens: 0
                  )
                end
              end
            end
          end
        end

        ChatMessage.new(
          role: "assistant",
          content: full_content,
          token_usage: usage,
          tool_calls: tool_calls.empty? ? nil : tool_calls
        )
      end
    end
  end

  Model.register("anthropic", Models::Anthropic)
end
