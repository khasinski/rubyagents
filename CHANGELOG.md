# Changelog

## 0.3.0

JRuby 10 support, interactive UI, and CI.

- **JRuby 10 support** -- Thread-based executor for JRuby where fork is unavailable; lipgloss gracefully skipped via `rescue LoadError`
- **Interactive status lines** -- Spinner shows "Executing..." / "Running tool_name..." during execution, resolves in-place to green dot (success) or red dot (error)
- **GitHub Actions CI** -- Build matrix with Ruby 3.2, 3.3, 3.4, and JRuby 10.0

## 0.2.0

Tools, MCP filtering, observability, and code agent improvements.

- **FileRead tool** -- Read file contents with path expansion and 50k char truncation
- **FileWrite tool** -- Write files with automatic parent directory creation
- **ListGems tool** -- Lists available Ruby gems; auto-included in CodeAgent
- **`tool_from_mcp`** -- Load a single tool from an MCP server by name
- **Run export** -- `to_h` / `to_json` on Memory, RunResult, and all step types for serialization
- **Richer callbacks** -- `Callback` base class with `on_run_start`, `on_step_start`, `on_step_end`, `on_tool_call`, `on_error`, `on_run_end`; backward-compatible with existing `step_callbacks`
- **`memory.replay`** -- Pretty-print a completed run with syntax-highlighted code and metrics
- **Code agent prompt** -- Tells the model about available Ruby stdlib and gems so it uses `net/http`, `json`, etc. without being asked

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
