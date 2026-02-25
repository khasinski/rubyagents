# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Rubyagents
  module Models
    class Ollama < Model
      DEFAULT_URL = "http://localhost:11434"

      def initialize(model_name)
        super
        @base_url = ENV.fetch("OLLAMA_HOST", DEFAULT_URL)
      end

      def generate(messages, tools: nil, &on_stream)
        body = {
          model: model_name,
          messages: format_messages(messages),
          stream: false
        }

        if tools&.any?
          body[:tools] = tools.map { |t| format_tool(t) }
        end

        if on_stream
          body[:stream] = true
          stream_request(body, &on_stream)
        else
          response = post("/api/chat", body)
          data = JSON.parse(response.body)

          if data["error"]
            raise Error, "Ollama error: #{data["error"]}"
          end

          content = data.dig("message", "content")
          usage = parse_usage(data)
          tool_calls = parse_tool_calls(data.dig("message", "tool_calls"))
          ChatMessage.new(role: "assistant", content: content, token_usage: usage, tool_calls: tool_calls)
        end
      end

      private

      def format_messages(messages)
        messages.map do |m|
          msg = { role: m[:role], content: m[:content] || "" }
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

      def parse_tool_calls(raw_calls)
        return nil unless raw_calls&.any?

        raw_calls.map do |tc|
          func = tc["function"] || {}
          args = func["arguments"]
          parsed_args = case args
          when String then JSON.parse(args)
          when Hash then args
          else {}
          end

          ToolCall.new(
            id: tc["id"] || SecureRandom.hex(12),
            function: ToolCallFunction.new(
              name: func["name"],
              arguments: parsed_args
            )
          )
        end
      end

      def parse_usage(data)
        return nil unless data["prompt_eval_count"] || data["eval_count"]
        TokenUsage.new(
          input_tokens: data["prompt_eval_count"] || 0,
          output_tokens: data["eval_count"] || 0
        )
      end

      def post(path, body)
        uri = URI("#{@base_url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 300 # Local models can be slow

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        http.request(request)
      end

      def stream_request(body, &on_stream)
        uri = URI("#{@base_url}/api/chat")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 300

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        full_content = +""
        usage = nil

        http.request(request) do |response|
          response.read_body do |chunk|
            chunk.split("\n").each do |line|
              next if line.strip.empty?
              parsed = JSON.parse(line)

              if (content = parsed.dig("message", "content"))
                full_content << content
                on_stream.call(content)
              end

              if parsed["done"]
                usage = parse_usage(parsed)
              end
            end
          end
        end

        ChatMessage.new(role: "assistant", content: full_content, token_usage: usage)
      end
    end
  end

  Model.register("ollama", Models::Ollama)
end
