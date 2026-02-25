# frozen_string_literal: true

require "open3"
require "json"

module Rubyagents
  module MCP
    class StdioTransport
      def initialize(command:)
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(*Array(command))
        @request_id = 0
        handshake!
      end

      def send_request(request:)
        @request_id += 1
        payload = { jsonrpc: "2.0", id: @request_id }.merge(request)
        write_message(payload)
        read_response(@request_id)
      end

      def close
        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
        @stderr.close unless @stderr.closed?
        @wait_thread.join
      end

      private

      def handshake!
        # Send initialize
        @request_id += 1
        init_request = {
          jsonrpc: "2.0",
          id: @request_id,
          method: "initialize",
          params: {
            protocolVersion: "2024-11-05",
            capabilities: {},
            clientInfo: { name: "rubyagents", version: Rubyagents::VERSION }
          }
        }
        write_message(init_request)
        read_response(@request_id)

        # Send initialized notification (no id)
        write_message({ jsonrpc: "2.0", method: "notifications/initialized" })
      end

      def write_message(hash)
        line = JSON.generate(hash)
        @stdin.puts(line)
        @stdin.flush
      end

      def read_response(expected_id)
        loop do
          line = @stdout.gets
          raise "MCP server closed connection" unless line
          msg = JSON.parse(line.strip)
          # Skip notifications (no id)
          next unless msg.key?("id")
          return msg if msg["id"] == expected_id
        end
      end
    end

    class MCPToolWrapper < Tool
      attr_reader :mcp_tool, :client

      def self.for(mcp_tool, client)
        klass = Class.new(self) do
          tool_name(mcp_tool["name"])
          description(mcp_tool["description"] || "")

          schema = mcp_tool.dig("inputSchema", "properties") || {}
          required_fields = mcp_tool.dig("inputSchema", "required") || []
          schema.each do |param_name, param_def|
            input param_name.to_sym,
                  type: (param_def["type"] || "string").to_sym,
                  description: param_def["description"] || "",
                  required: required_fields.include?(param_name)
          end
        end
        klass.new(mcp_tool, client)
      end

      def initialize(mcp_tool, client)
        @mcp_tool = mcp_tool
        @client = client
      end

      def call(**kwargs)
        response = @client.send_request(
          request: {
            method: "tools/call",
            params: { name: @mcp_tool["name"], arguments: kwargs.transform_keys(&:to_s) }
          }
        )
        # Extract text content from MCP response
        content = response.dig("result", "content") || []
        content.filter_map { |c| c["text"] if c["type"] == "text" }.join("\n")
      end
    end
  end

  def self.tools_from_mcp(command:)
    transport = MCP::StdioTransport.new(command: command)
    response = transport.send_request(request: { method: "tools/list", params: {} })
    tools = response.dig("result", "tools") || []
    tools.map { |t| MCP::MCPToolWrapper.for(t, transport) }
  end

  def self.tool_from_mcp(command:, tool_name:)
    transport = MCP::StdioTransport.new(command: command)
    response = transport.send_request(request: { method: "tools/list", params: {} })
    tools = response.dig("result", "tools") || []
    tool_def = tools.find { |t| t["name"] == tool_name }

    unless tool_def
      available = tools.map { |t| t["name"] }.join(", ")
      raise ArgumentError, "Tool #{tool_name.inspect} not found. Available: #{available}"
    end

    MCP::MCPToolWrapper.for(tool_def, transport)
  end
end
