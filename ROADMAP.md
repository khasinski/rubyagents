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

Broader model support and tool discovery.

- [ ] **Google Gemini adapter** -- Direct adapter for Gemini API (large user base, good tool calling support).
- [ ] **LiteLLM-style universal adapter** -- Single adapter that proxies to any OpenAI-compatible endpoint. Covers Azure, Groq, Together, Fireworks, local vLLM, etc. without one-off adapters.
- [ ] **Rate limiting** -- `requests_per_minute` on model adapters with automatic backoff/retry on 429s.
- [ ] **More built-in tools** -- Google search (API-based, more reliable than DDG scraping), Wikipedia search, file read/write tools.
- [ ] **Tool.from_mcp** -- Load a single tool from an MCP server by name (vs loading all tools from a server).

## Phase 7 -- Observability & debugging (medium impact, medium effort)

Understanding what agents actually do.

- [ ] **Structured logging** -- JSON-structured logs per step with run_id, step_number, thought, action, observation, timing, tokens. Emit to any Ruby logger.
- [ ] **`memory.replay`** -- Pretty-print a completed run to the terminal (like smolagents' `agent.replay()`).
- [ ] **Run export** -- Serialize a run (memory + steps + metadata) to JSON for later analysis or replay.
- [ ] **Callbacks for observability** -- Richer callback interface: `on_step_start`, `on_step_end`, `on_tool_call`, `on_error`. Current `step_callbacks` only fires after completion.

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
- **MLX/vLLM adapters** -- Python-only inference runtimes. Ollama covers local models.
