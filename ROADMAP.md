# Roadmap

Gaps identified by comparing rubyagents with [smolagents](https://github.com/huggingface/smolagents), prioritized for Ruby developers building agents.

## Phase 5 -- Core DX (high impact, low effort)

These make the framework usable for real work.

- [x] **MCP client for tools** -- Load tools from any MCP server (stdio + HTTP). This is the single biggest ecosystem unlock since MCP servers already exist for databases, APIs, file systems, browsers, etc. Ruby devs shouldn't have to rewrite tools that already exist.
- [x] **Structured output** -- Let agents return typed results (not just strings). Accept a schema or Data class, validate the final answer against it. Enables agents as reliable building blocks in larger apps.
- [x] **Prompt customization** -- Expose `PromptTemplates` object (system prompt, planning, managed agent) so users can override prompts without subclassing. Add `instructions:` parameter for injecting custom rules.
- [x] **`agent.step()` method** -- Single-step execution for debugging and building custom UIs. Returns the step, lets the caller inspect/modify memory before continuing.
- [x] **`final_answer_checks`** -- List of validation procs run before accepting a final answer. If any returns false, the agent keeps going. Cheap way to add guardrails.

## Phase 6 -- Model & tool ecosystem (high impact, medium effort)

Broader model support and tool discovery. The RubyLLM migration (replacing 3 hand-rolled adapters with a single wrapper) completed most of the model items here.

- [x] **RubyLLM universal adapter** -- Replaced OpenAI, Anthropic, and Ollama adapters with a single RubyLLM wrapper. Supports 800+ models across OpenAI, Anthropic, Gemini, DeepSeek, OpenRouter, Ollama, and any OpenAI-compatible endpoint. Auto-configures from env vars.
- [x] **Rate limiting (basic)** -- RubyLLM provides built-in `max_retries` and `retry_interval` for 429s. Per-minute quotas are not yet exposed.
- [x] **More built-in tools** -- File read/write tools. Google search and Wikipedia search remain TODO.
- [x] **Tool.from_mcp** -- Load a single tool from an MCP server by name (vs loading all tools from a server).

## Phase 7 -- Observability & debugging (medium impact, medium effort)

Understanding what agents actually do.

- [ ] **Structured logging** -- JSON-structured logs per step with run_id, step_number, thought, action, observation, timing, tokens. Emit to any Ruby logger.
- [x] **`memory.replay`** -- Pretty-print a completed run to the terminal (like smolagents' `agent.replay()`).
- [x] **Run export** -- Serialize a run (memory + steps + metadata) to JSON for later analysis or replay.
- [x] **Callbacks for observability** -- Richer callback interface: `on_step_start`, `on_step_end`, `on_tool_call`, `on_error`. Current `step_callbacks` only fires after completion.

## Phase 8 -- Sandboxing & security (medium impact, high effort)

For production use where agent code can't be trusted.

- [ ] **Docker executor** -- Run agent code in a Docker container instead of a fork. Filesystem isolation, network control, resource limits.
- [ ] **Import/require allowlist** -- Restrict which Ruby gems/stdlib modules agent code can load in the sandbox (like smolagents' `additional_authorized_imports`).
- [ ] **Operation count limit** -- Cap iterations/operations in the sandbox to prevent infinite loops eating CPU (smolagents caps at 1M operations).

## Phase 9 -- Advanced features (lower priority, nice to have)

- [ ] **Agent serialization** -- `agent.save(dir)` / `Agent.load(dir)` for persisting agent configuration (tools, prompts, model, settings).
- [ ] **Media types in tools** -- Support image/audio inputs and outputs for multimodal agents.
- [ ] **Async/parallel tool calls** -- ToolCallingAgent processes multiple tool calls concurrently (like smolagents' `max_tool_threads`).
- [ ] **Web UI** -- Lightweight web interface for interactive agent sessions (alternative to CLI). Could be a simple Rack app or use Hotwire.
- [ ] **Persistent memory** -- Long-term memory across runs (conversation history, learned facts). Could be file-based or backed by SQLite.

## Not planned

These exist in smolagents but don't fit rubyagents' design goals:

- **Hub sharing** -- No equivalent to HuggingFace Hub in Ruby. Gems are the distribution mechanism.
- **LangChain/Gradio interop** -- Python-specific ecosystems.
- **WASM executor** -- Ruby WASM support is too immature.
- **MLX/vLLM adapters** -- Python-only inference runtimes. RubyLLM covers local models via Ollama.
