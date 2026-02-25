#!/usr/bin/env ruby
# frozen_string_literal: true

# Mock MCP server for testing. Reads JSON-RPC from stdin, responds on stdout.

require "json"

$stdout.sync = true

loop do
  line = $stdin.gets
  break unless line

  request = JSON.parse(line.strip)

  # Skip notifications (no id)
  next unless request.key?("id")

  response = case request["method"]
  when "initialize"
    {
      jsonrpc: "2.0",
      id: request["id"],
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "mock-mcp", version: "1.0.0" }
      }
    }
  when "tools/list"
    {
      jsonrpc: "2.0",
      id: request["id"],
      result: {
        tools: [
          {
            name: "echo",
            description: "Echoes the input back",
            inputSchema: {
              type: "object",
              properties: {
                message: { type: "string", description: "Message to echo" }
              },
              required: ["message"]
            }
          },
          {
            name: "add",
            description: "Adds two numbers",
            inputSchema: {
              type: "object",
              properties: {
                a: { type: "integer", description: "First number" },
                b: { type: "integer", description: "Second number" }
              },
              required: %w[a b]
            }
          }
        ]
      }
    }
  when "tools/call"
    tool_name = request.dig("params", "name")
    args = request.dig("params", "arguments") || {}

    text = case tool_name
    when "echo"
      args["message"] || ""
    when "add"
      ((args["a"] || 0).to_i + (args["b"] || 0).to_i).to_s
    else
      "Unknown tool: #{tool_name}"
    end

    {
      jsonrpc: "2.0",
      id: request["id"],
      result: {
        content: [{ type: "text", text: text }]
      }
    }
  else
    {
      jsonrpc: "2.0",
      id: request["id"],
      error: { code: -32601, message: "Method not found" }
    }
  end

  $stdout.puts JSON.generate(response)
end
