# frozen_string_literal: true

require "spec_helper"

MOCK_SERVER = File.expand_path("../fixtures/mock_mcp_server.rb", __dir__)

RSpec.describe Rubyagents::MCP do
  describe Rubyagents::MCP::StdioTransport do
    it "performs handshake and accepts requests" do
      transport = Rubyagents::MCP::StdioTransport.new(command: ["ruby", MOCK_SERVER])

      response = transport.send_request(request: { method: "tools/list", params: {} })
      tools = response.dig("result", "tools")

      expect(tools).to be_an(Array)
      expect(tools.size).to eq(2)
      expect(tools.map { |t| t["name"] }).to contain_exactly("echo", "add")

      transport.close
    end

    it "can call tools" do
      transport = Rubyagents::MCP::StdioTransport.new(command: ["ruby", MOCK_SERVER])

      response = transport.send_request(
        request: {
          method: "tools/call",
          params: { name: "echo", arguments: { "message" => "hello" } }
        }
      )

      content = response.dig("result", "content")
      expect(content.first["text"]).to eq("hello")

      transport.close
    end
  end

  describe Rubyagents::MCP::MCPToolWrapper do
    it "maps MCP tool schema to rubyagents input DSL" do
      mcp_tool = {
        "name" => "greet",
        "description" => "Greets someone",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "name" => { "type" => "string", "description" => "Person name" }
          },
          "required" => ["name"]
        }
      }

      client = instance_double(Rubyagents::MCP::StdioTransport)
      wrapper = Rubyagents::MCP::MCPToolWrapper.for(mcp_tool, client)

      expect(wrapper.class.tool_name).to eq("greet")
      expect(wrapper.class.description).to eq("Greets someone")
      expect(wrapper.class.inputs).to have_key(:name)
      expect(wrapper.class.inputs[:name][:type]).to eq(:string)
    end

    it "delegates call to MCP client" do
      mcp_tool = {
        "name" => "echo",
        "description" => "Echoes input",
        "inputSchema" => {
          "type" => "object",
          "properties" => {
            "message" => { "type" => "string", "description" => "Message" }
          },
          "required" => ["message"]
        }
      }

      client = instance_double(Rubyagents::MCP::StdioTransport)
      allow(client).to receive(:send_request).and_return({
        "result" => {
          "content" => [{ "type" => "text", "text" => "hello back" }]
        }
      })

      wrapper = Rubyagents::MCP::MCPToolWrapper.for(mcp_tool, client)
      result = wrapper.call(message: "hello")

      expect(result).to eq("hello back")
      expect(client).to have_received(:send_request).with(
        request: {
          method: "tools/call",
          params: { name: "echo", arguments: { "message" => "hello" } }
        }
      )
    end
  end

  describe "Rubyagents.tools_from_mcp" do
    it "loads tools from mock MCP server end-to-end" do
      tools = Rubyagents.tools_from_mcp(command: ["ruby", MOCK_SERVER])

      expect(tools.size).to eq(2)
      expect(tools.map { |t| t.class.tool_name }).to contain_exactly("echo", "add")

      # Test calling a tool
      echo_tool = tools.find { |t| t.class.tool_name == "echo" }
      expect(echo_tool.call(message: "test")).to eq("test")

      add_tool = tools.find { |t| t.class.tool_name == "add" }
      expect(add_tool.call(a: 3, b: 5)).to eq("8")
    end
  end
end
