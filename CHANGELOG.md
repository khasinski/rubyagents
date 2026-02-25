# Changelog

## 0.1.0

Initial release.

- **CodeAgent** -- LLM writes and executes Ruby code in a sandboxed fork
- **ToolCallingAgent** -- LLM calls tools via structured tool_calls (OpenAI-style)
- **Model adapters** -- OpenAI, Anthropic, and Ollama out of the box
- **Tool DSL** -- Define tools as classes or inline blocks
- **MCP client** -- Load tools from any MCP server via stdio transport
- **Structured output** -- Validate final answers against JSON Schema or custom procs
- **Prompt customization** -- Override system prompts, planning prompts, or inject instructions
- **Final answer checks** -- Validation procs that can reject and retry answers
- **Step-by-step execution** -- `agent.step()` for debugging and custom UIs
- **Planning** -- Optional periodic re-planning during long runs
- **Managed agents** -- Nest agents as tools for multi-agent workflows
- **CLI** -- `rubyagents` command with interactive mode, tool loading, and MCP support
