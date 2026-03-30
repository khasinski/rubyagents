# Gemlings

[![Gem Version](https://badge.fury.io/rb/gemlings.svg)](https://rubygems.org/gems/gemlings)
[![CI](https://github.com/khasinski/gemlings/actions/workflows/ci.yml/badge.svg)](https://github.com/khasinski/gemlings/actions/workflows/ci.yml)

*Small, autonomous agents running Ruby snippets.*

Your LLM writes and executes Ruby code -- not JSON blobs. Tool calls are method calls, variables persist between steps, and the full power of Ruby is available to the agent at every turn. Inspired by [smolagents](https://github.com/huggingface/smolagents).

![gemlings demo](demo.gif)

## Quick start

```bash
gem install gemlings
```

```ruby
require "gemlings"

agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514")
agent.run("What is the 118th Fibonacci number?")
```

The agent thinks, writes Ruby, executes it in a sandbox, and returns the answer.

## Agent types

**CodeAgent** writes Ruby code that runs in a sandboxed fork (MRI) or thread (JRuby). Tools are methods the model can call directly. Variables persist across steps.

```ruby
agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514")
```

**ToolCallingAgent** uses structured tool calls (OpenAI function calling style). Better for models with strong native tool support.

```ruby
agent = Gemlings::ToolCallingAgent.new(model: "openai/gpt-4o")
```

## Models

Pass `provider/model_name`. Supports Anthropic, OpenAI, Google Gemini, DeepSeek, OpenRouter, and Ollama.

```ruby
Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514")
Gemlings::CodeAgent.new(model: "openai/gpt-4o")
Gemlings::CodeAgent.new(model: "ollama/qwen2.5:3b")
```

Set API keys via environment variables: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc.

## Tools

Six built-in tools: `web_search`, `visit_webpage`, `file_read`, `file_write`, `user_input`, and `list_gems` (auto-included in CodeAgent).

Define your own as a class:

```ruby
class StockPrice < Gemlings::Tool
  tool_name "stock_price"
  description "Gets the current stock price for a ticker symbol"
  input :ticker, type: :string, description: "Stock ticker symbol (e.g. AAPL)"
  output_type :number

  def call(ticker:)
    182.52
  end
end

agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514", tools: [StockPrice])
```

Or inline:

```ruby
weather = Gemlings.tool(:weather, "Gets weather for a city", city: "City name") do |city:|
  "72F and sunny in #{city}"
end
```

### MCP tools

Load tools from any [MCP](https://modelcontextprotocol.io/) server:

```ruby
tools = Gemlings.tools_from_mcp(command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"])

# Or load a single tool by name
tool = Gemlings.tool_from_mcp(command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"], tool_name: "read_file")
```

### RubyLLM tools

Use existing [RubyLLM](https://rubyllm.com) tools directly:

```ruby
class SearchTool < RubyLLM::Tool
  description "Search the web"
  param :query, type: :string, desc: "Search query"
  def execute(query:) = "results for #{query}"
end

agent = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  tools: [Gemlings.tool_from_ruby_llm(SearchTool)]
)
```

## Multi-agent workflows

Nest agents as tools. The manager agent calls sub-agents by name:

```ruby
researcher = Gemlings::ToolCallingAgent.new(
  model: "openai/gpt-4o",
  name: "researcher",
  description: "Researches topics on the web",
  tools: [Gemlings::WebSearch]
)

manager = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  agents: [researcher]
)

manager.run("Find out when Ruby 3.4 was released and summarize the key features")
```

RubyLLM agents work too:

```ruby
class Researcher < RubyLLM::Agent
  model "openai/gpt-4o"
  tools SearchTool
  instructions "You are a research assistant."
end

manager = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  agents: [Gemlings.agent_from_ruby_llm(Researcher, name: "researcher", description: "Researches topics")]
)
```

## Output validation

Validate final answers against a JSON Schema:

```ruby
agent = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  output_type: {
    "type" => "object",
    "required" => ["name", "age"],
    "properties" => {
      "name" => { "type" => "string" },
      "age" => { "type" => "integer" }
    }
  }
)
```

Or add custom checks that reject answers and force retries:

```ruby
agent = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  final_answer_checks: [
    ->(answer, memory) { answer.length > 10 },
    ->(answer, memory) { !answer.include?("I don't know") }
  ]
)
```

## Observability

### Callbacks

```ruby
class Logger < Gemlings::Callback
  def on_run_start(task:, agent:) = puts("Starting: #{task}")
  def on_step_end(step:, agent:) = puts("Step done: #{step.duration}s")
  def on_tool_call(tool_name:, arguments:, agent:) = puts("Calling #{tool_name}")
  def on_run_end(result:, agent:) = puts("Done: #{result}")
end

agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514", callbacks: [Logger.new])
```

### Export and replay

```ruby
result = agent.run("What is 2+2?", return_full_result: true)
result.to_json  # serialize the full run

agent.memory.replay  # pretty-print with syntax-highlighted code
```

## Step-by-step execution

Run one step at a time for debugging or custom UIs:

```ruby
agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514")

agent.step("What is 2+2?")
agent.step until agent.done?

puts agent.final_answer_value
```

## Prompt customization

```ruby
# Append instructions
agent = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  instructions: "Always respond in French. Use metric units."
)

# Or fully replace the system prompt
templates = Gemlings::PromptTemplates.new(
  system_prompt: "You are a data analyst. Tools: {{tool_descriptions}}"
)

agent = Gemlings::CodeAgent.new(model: "anthropic/claude-sonnet-4-20250514", prompt_templates: templates)
```

## Planning

Enable periodic re-planning during long runs:

```ruby
agent = Gemlings::CodeAgent.new(
  model: "anthropic/claude-sonnet-4-20250514",
  planning_interval: 3,
  max_steps: 15
)
```

## CLI

```bash
gemlings "What is the 10th prime number?"
gemlings -m openai/gpt-4o -t web_search "Who won the latest Super Bowl?"
gemlings -a tool_calling -m openai/gpt-4o "What is 6 * 7?"
gemlings --mcp "npx -y @modelcontextprotocol/server-filesystem /tmp" "List files in /tmp"
gemlings -i  # interactive mode
gemlings -S "What is 2+2?"  # stream tokens to terminal
```

## Configuration

| Option | Default | Description |
|---|---|---|
| `model:` | -- | `"provider/model_name"` |
| `tools:` | `[]` | Array of Tool classes or instances |
| `agents:` | `[]` | Sub-agents (become callable tools) |
| `max_steps:` | `10` | Maximum steps before stopping |
| `planning_interval:` | `nil` | Re-plan every N steps |
| `instructions:` | `nil` | Extra instructions appended to system prompt |
| `prompt_templates:` | `nil` | Custom `PromptTemplates` instance |
| `output_type:` | `nil` | JSON Schema hash or validation Proc |
| `final_answer_checks:` | `[]` | Procs `(answer, memory) -> bool` |
| `callbacks:` | `[]` | Array of `Callback` instances |
| `step_callbacks:` | `[]` | Procs `(step, agent:) -> void` |
| `executor:` | auto | CodeAgent sandbox: `:fork`, `:thread`, or `:box` (Ruby 4.0+) |

Requires Ruby 3.2+. JRuby 10+ is also supported. On Ruby 4.0+ with `RUBY_BOX=1`, the `:box` executor adds namespace isolation via `Ruby::Box`.

## Ecosystem

- [gemlings_browser](https://github.com/parolkar/gemlings_browser) -- Browser automation tools for gemlings agents

## License

MIT
