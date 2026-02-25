# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Rubyagents
  module Models
    class OpenAI < Model
      API_URL = "https://api.openai.com/v1/chat/completions"

      def initialize(model_name)
        super
        @api_key = ENV.fetch("OPENAI_API_KEY") {
          raise Error, "OPENAI_API_KEY environment variable is required"
        }
      end

      def generate(messages, tools: nil, &on_stream)
        body = {
          model: model_name,
          messages: format_messages(messages)
        }

        if tools&.any?
          body[:tools] = tools.map { |t| format_tool(t) }
        end

        if on_stream
          body[:stream] = true
          body[:stream_options] = { include_usage: true }
          stream_request(body, &on_stream)
        else
          response = post(body)
          data = JSON.parse(response.body)

          if data["error"]
            raise Error, "OpenAI API error: #{data["error"]["message"]}"
          end

          parse_chat_response(data)
        end
      end

      private

      def format_messages(messages)
        messages.map do |m|
          msg = { role: m[:role], content: m[:content] }
          if m[:tool_calls]
            msg[:tool_calls] = m[:tool_calls].map do |tc|
              {
                id: tc.id,
                type: "function",
                function: { name: tc.function.name, arguments: JSON.generate(tc.function.arguments) }
              }
            end
          end
          msg
        end
      end

      def format_tool(schema)
        {
          type: "function",
          function: {
            name: schema[:name],
            description: schema[:description],
            parameters: schema[:parameters]
          }
        }
      end

      def parse_chat_response(data)
        message = data.dig("choices", 0, "message")
        content = message["content"]
        usage = parse_usage(data["usage"])
        tool_calls = parse_tool_calls(message["tool_calls"])
        ChatMessage.new(role: "assistant", content: content, token_usage: usage, tool_calls: tool_calls)
      end

      def parse_tool_calls(raw_calls)
        return nil unless raw_calls&.any?

        raw_calls.map do |tc|
          args = tc.dig("function", "arguments")
          parsed_args = args.is_a?(String) ? JSON.parse(args) : (args || {})
          ToolCall.new(
            id: tc["id"],
            function: ToolCallFunction.new(
              name: tc.dig("function", "name"),
              arguments: parsed_args
            )
          )
        end
      end

      def parse_usage(usage)
        return nil unless usage
        TokenUsage.new(
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0
        )
      end

      def post(body)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        http.request(request)
      end

      def stream_request(body, &on_stream)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        full_content = +""
        usage = nil
        tool_calls_data = {}

        http.request(request) do |response|
          response.read_body do |chunk|
            chunk.split("\n").each do |line|
              next unless line.start_with?("data: ")
              data = line.sub("data: ", "")
              next if data == "[DONE]"

              parsed = JSON.parse(data)
              delta = parsed.dig("choices", 0, "delta")

              if delta
                if delta["content"]
                  full_content << delta["content"]
                  on_stream.call(delta["content"])
                end

                # Accumulate streamed tool calls
                if delta["tool_calls"]
                  delta["tool_calls"].each do |tc_delta|
                    idx = tc_delta["index"]
                    tool_calls_data[idx] ||= { "id" => nil, "function" => { "name" => "", "arguments" => "" } }
                    tool_calls_data[idx]["id"] = tc_delta["id"] if tc_delta["id"]
                    if tc_delta["function"]
                      tool_calls_data[idx]["function"]["name"] += tc_delta["function"]["name"] || ""
                      tool_calls_data[idx]["function"]["arguments"] += tc_delta["function"]["arguments"] || ""
                    end
                  end
                end
              end

              usage = parse_usage(parsed["usage"]) if parsed["usage"]
            end
          end
        end

        tool_calls = if tool_calls_data.any?
          parse_tool_calls(tool_calls_data.values)
        end

        ChatMessage.new(role: "assistant", content: full_content, token_usage: usage, tool_calls: tool_calls)
      end
    end
  end

  Model.register("openai", Models::OpenAI)
end
