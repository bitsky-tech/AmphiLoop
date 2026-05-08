---
name: bridgic-amphibious
description: "Build agents with the Bridgic Amphibious dual-mode framework — combining LLM-driven (agent) and deterministic (workflow) execution with automatic fallback, an async-generator yield protocol with six scope-validated primitives (ActionCall, HumanCall, LLMCall, AgentCall, ThinkCall, RETURN), pluggable @human_channel HITL handlers, an optional WorkerRunner escape hatch for external runtimes, and a built-in tool surface (shell, filesystem, search, HITL) auto-injected into every agent. Use when: (1) writing code that imports from bridgic.amphibious, (2) creating AmphibiousAutoma subclasses, (3) defining CognitiveWorker think units invoked via yield ThinkCall(...), (4) implementing on_agent / on_workflow / observation / before_action / after_action as async-generator template methods, (5) working with CognitiveContext, the Exposure system, or cognitive policies, (6) wiring human-in-the-loop via @human_channel handlers, HumanCall yields, or the auto-injected request_human tool, (7) using or filtering the auto-injected built-in tools (bash, read_file/write_file/edit_file, glob, grep, request_human) via the builtin_tools class attribute or arun kwarg, (8) plugging an external agent runtime via the WorkerRunner Protocol, (9) scaffolding a new amphibious project via CLI, (10) any task involving the bridgic-amphibious framework."
---

# Bridgic Amphibious

Dual-mode agent framework: agents operate in LLM-driven (`on_agent`) and deterministic (`on_workflow`) modes with automatic fallback between them. All template methods are **async generators** that yield framework primitives; the dispatcher routes each yield to its handler and sends the result back via `asend()`.

## Dependencies

A bridgic-amphibious project requires the following packages:

| Package | Description |
|---------|-------------|
| `bridgic-core` | Core framework (Worker, Automa, GraphAutoma) |
| `bridgic-amphibious` | Dual-mode agent framework |
| `bridgic-llms-openai` | LLM provider (only required for `AGENT` / `AMPHIFLOW` modes) |
| `python-dotenv` | `.env` file loading |

Before using this package, you need to install the dependencies by using the provided install script:

```bash
bash "skills/bridgic-amphibious/scripts/install-deps.sh" "$PWD"
```

The script checks uv availability, initializes a uv project if needed, installs any missing packages via `uv add`, and runs `uv sync` to finalize the environment. When it exits successfully the project is fully initialized and ready to use — no manual `uv add` / `uv sync` follow-up is required.

## LLM Setup

Amphibious agents accept a `BaseLlm` instance with `astructure_output` protocol from a bridgic LLM provider package. The LLM is required for `AGENT` and `AMPHIFLOW` modes; pure `WORKFLOW` mode can run without one.

```python
from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration

llm = OpenAILlm(
    api_key="your-api-key",
    api_base="https://api.openai.com/v1",  # or custom endpoint
    configuration=OpenAIConfiguration(model="gpt-4o", temperature=0.0),
)
```

Other providers with same protocol: `bridgic.llms.vllm.VllmServerLlm` (self-hosted vLLM), `bridgic.llms.openai_like.OpenAILikeLlm` (OpenAI-compatible APIs).

## Quick Start

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, CognitiveWorker, think_unit,
    ThinkCall, RETURN,
)
from bridgic.core.agentic.tool_specs import FunctionToolSpec

async def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny, 22°C in {city}"

class WeatherAgent(AmphibiousAutoma[CognitiveContext]):
    planner = think_unit(
        CognitiveWorker.inline("Look up weather and provide a summary."),
        max_attempts=5,
    )

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("planner")
        # Final answer auto-captured from the finishing think step.

agent = WeatherAgent(llm=llm, verbose=True)
result = await agent.arun(
    goal="Check the weather in Tokyo and London.",
    tools=[FunctionToolSpec.from_raw(get_weather)],
)
```

## Project Scaffolding

Use the CLI to bootstrap a new project:

```bash
bridgic-amphibious create
bridgic-amphibious create --task "Navigate to example.com and extract data"
bridgic-amphibious create --base-dir /path/to/project
```

Creates a single `amphi.py` in the target directory (default: cwd). The template includes a custom `CognitiveContext` subclass, an `AmphibiousAutoma` subclass with a `think_unit` declaration, and stubs for both `on_agent` (using `yield ThinkCall("main_think")`) and `on_workflow`. Runtime concerns (LLM credentials, entry script) are intentionally left to the caller.

## Core Concepts

**Agent = Think Units + Yield-Based Orchestration.** Agents are defined by declaring `CognitiveWorker` think units and orchestrating them in `on_agent()` / `on_workflow()` async generators that yield framework primitives.

**Four-layer architecture:**
1. `Exposure` — data visibility abstraction (LayeredExposure / EntireExposure)
2. `CognitiveContext` — state container (goal, tools, skills, history)
3. `CognitiveWorker` — pure thinking unit (observe-think-act)
4. `AmphibiousAutoma` — orchestration engine (mode routing, dispatcher, lifecycle)

**OTC Cycle:** Observe → Think → Act, with hook points at each phase.

**Four RunModes:** `AGENT` (LLM-driven), `WORKFLOW` (deterministic), `AMPHIFLOW` (workflow + agent fallback), `AUTO` (auto-detect from overridden methods, default).

**`AUTO` resolution:** only `on_agent` overridden → `AGENT`; only `on_workflow` overridden → `WORKFLOW`; both overridden → `AMPHIFLOW`.

## Yield Primitives & Scope Rules

Template methods are async generators. The dispatcher routes each yielded primitive to its handler and sends the result back via `asend()`. Six primitives exist; **scope rules** restrict where each can appear:

| Primitive | `on_workflow` | `on_agent` | hooks (`observation` / `before_action` / `after_action`) |
|-----------|:-------------:|:----------:|:-------------------------------------------------------:|
| `ActionCall(name, **args)` — deterministic single-tool exec | ✓ | ✓ | ✓ |
| `HumanCall(prompt=..., channel=...)` — pause for human input | ✓ | ✓ | ✓ |
| `LLMCall.chat / .structure_output / .tool_selector(...)` — direct LLM call | ✓ | ✓ | ✓ |
| `AgentCall(goal=..., tools=..., skills=..., history=...)` — sub-agent with context scope | ✓ | ✗ | ✗ |
| `ThinkCall(name, **overrides)` — invoke a class-level `think_unit` by name | ✗ | ✓ | ✗ |
| `RETURN(value)` — emit a return value from an async generator | ✓ | ✓ | ✓ (only `observation` & `before_action` use it) |

A scope violation raises `RuntimeError` at dispatch time:
- `AgentCall` outside `on_workflow` → fails (AgentCall is the deterministic→autonomous transition; once inside `on_agent`, keep thinking via `ThinkCall`).
- `ThinkCall` outside `on_agent` → fails (`ThinkCall` invokes the cognitive runtime; that lives only inside the LLM-driven flow).

**`RETURN` semantics.** PEP 525 forbids `return value` in async generators. Yield `RETURN(value)` instead — the dispatcher captures it, closes the generator, and uses the value: as the hook's return for `observation` / `before_action`, or as `agent.final_answer` for top-level `on_agent` / `on_workflow`.

## Built-in Tools

Every `AmphibiousAutoma` agent receives seven built-in tools in `context.tools` automatically during `arun()` — no manual wiring. Tool names are snake_case and work in every mode (LLM-called in agent mode, `yield ActionCall("name", ...)` in workflow mode).

| Tool | What it does |
|------|--------------|
| `request_human` | Pause and ask the human operator a question (HITL) |
| `bash` | Execute a shell command (stdout / stderr / exit_code captured) |
| `read_file` | Read a file with line numbers; required before `write_file` / `edit_file` modify it |
| `write_file` | Create a new file, or overwrite an existing one (read-before-overwrite enforced) |
| `edit_file` | Exact-string replacement with uniqueness check; `replace_all` for refactors |
| `glob` | Find files by pattern, sorted by mtime |
| `grep` | Regex content search across files |

Subclasses can opt out of specific built-ins via a class-level frozenset, and runs can override per-call:

```python
class ReadOnlyAgent(AmphibiousAutoma[CognitiveContext]):
    # Only these three are injected; bash / write / edit are unavailable.
    builtin_tools = frozenset({"request_human", "read_file", "grep"})

# Runtime override (wins over class attr); empty iterable opts out entirely.
await agent.arun(goal="...", builtin_tools=["request_human"])
```

Unknown names raise `ValueError` at `arun()` entry — typos surface immediately rather than silently producing a missing-tool agent. User-supplied tools whose name collides with a built-in win (deduplicated by `tool_name`).

`write_file` and `edit_file` enforce a read-before-modify invariant: the path must have been read with `read_file` first, AND the file must not have been changed externally since. The tracker is reset at every `arun()` entry, so the invariant is scoped to a single run.

For the full per-tool parameter list, error contracts, and filter resolution rules see [references/api-reference.md](references/api-reference.md#built-in-tools).

## Key Patterns

### Agent Mode — LLM decides

```python
from bridgic.amphibious import ThinkCall

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(CognitiveWorker.inline("Decide next step."), max_attempts=10)

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
```

### Workflow Mode — Developer decides

```python
from bridgic.amphibious import ActionCall, RETURN

class MyWorkflow(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx):
        result = yield ActionCall("tool_name", arg1="value")
        # result is List[ToolResult]
        yield RETURN(result[0].result)

# Pure workflow mode does not need an LLM.
await MyWorkflow().arun(goal="...", tools=[...])
```

### Amphiflow Mode — Workflow with agent fallback

```python
from bridgic.amphibious import RunMode, ActionCall, ThinkCall

class MyHybrid(AmphibiousAutoma[CognitiveContext]):
    fixer = think_unit(CognitiveWorker.inline("Fix the problem."), max_attempts=5)

    async def on_agent(self, ctx):
        yield ThinkCall("fixer")

    async def on_workflow(self, ctx):
        yield ActionCall("fill_field", name="user", value="john")
        yield ActionCall("click_button", name="submit")

await MyHybrid(llm=llm).arun(
    goal="...", tools=[...],
    mode=RunMode.AMPHIFLOW, max_consecutive_fallbacks=2,
)
```

### Direct LLM Call from Workflow

```python
from bridgic.amphibious import ActionCall, LLMCall, RETURN

class Summarizer(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx):
        files = yield ActionCall("glob", pattern="**/*.py", path="/abs/repo")
        summary = yield LLMCall.chat(f"Summarize this repo:\n{files[0].result}")
        yield RETURN(summary)
```

`LLMCall` has three protocols: `chat` (returns `str`), `structure_output` (typed Pydantic instance), `tool_selector` (`(List[ToolCall], Optional[str])`).

### Sub-Agent Delegation

```python
from bridgic.amphibious import ActionCall, AgentCall

class ResearchHybrid(AmphibiousAutoma[CognitiveContext]):
    investigator = think_unit(CognitiveWorker.inline("Investigate."), max_attempts=10)

    async def on_agent(self, ctx):
        yield ThinkCall("investigator")

    async def on_workflow(self, ctx):
        yield ActionCall("search_price", platform="Amazon", product="laptop")
        # Recursively re-enter on_agent in a snapshotted context.
        yield AgentCall(
            goal="Analyze prices and decide if we need more platforms.",
            tools=["search_price", "request_human"],   # name-filter on ctx.tools
        )
```

`AgentCall` scopes the sub-agent's *context* (what it sees) — not how it thinks. For a single named cognitive step, declare a `think_unit` and `yield ThinkCall("name")` from inside `on_agent` instead.

### Human-in-the-Loop

Three entry points share one event channel — the `@human_channel` registry. They all route through the same dispatch path:

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, CognitiveWorker, think_unit,
    ActionCall, HumanCall, ThinkCall, human_channel,
)

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(CognitiveWorker.inline("Execute step."), max_attempts=10)

    # Entry 1: register a custom human-input handler.
    @human_channel  # bare → channel name = "terminal"
    async def terminal(self, prompt: str) -> str:
        return input(f"\n> {prompt}\n")

    # Or with an explicit channel name:
    @human_channel("feishu")
    async def ask_feishu(self, prompt: str) -> str:
        return await feishu_client.send_and_wait(prompt)

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
        # Entry 2: HumanCall in any flow (channel=None → implicit default
        # if exactly one channel registered; otherwise specify channel="...").
        feedback = yield HumanCall(prompt="Proceed?")

    async def on_workflow(self, ctx):
        yield ActionCall("do_something", arg="value")
        feedback = yield HumanCall(prompt="Confirm?", channel="feishu")

# Entry 3 is automatic — the built-in `request_human` tool is already in
# context.tools, so the LLM can call it without listing it in tools=[...].
# It internally routes through the same @human_channel registry.
await MyAgent(llm=llm).arun(goal="...", tools=[my_tool])
```

If no `@human_channel` is registered, `HumanCall` falls through to a built-in stdin handler. With one channel registered it becomes the implicit default; with multiple, `HumanCall(channel="...")` must be explicit (or the LLM-facing `request_human` tool will need a registered default).

### External Worker Runtime — `WorkerRunner`

Plug an external agent runtime (Claude Code, OpenAI Agents, a bespoke ReAct stack) in via the `WorkerRunner` Protocol — a single `async run(agent, ctx)` callback that takes full responsibility for completing the sub-task:

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, WorkerRunner,
    ThinkCall, think_unit,
)

class ClaudeCodeRunner:
    """Plug-in WorkerRunner — manages its own loop, tools, history."""
    async def run(self, agent: AmphibiousAutoma, ctx: CognitiveContext) -> None:
        # subprocess out to claude, feed it ctx.goal, write the resulting
        # transcript into ctx.cognitive_history.
        ...

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    external = think_unit(ClaudeCodeRunner())  # auto-detected as WorkerRunner path

    async def on_agent(self, ctx):
        yield ThinkCall("external")
```

The dispatcher detects that the worker is not a `CognitiveWorker` and skips the observe-think-act cycle, calling `run(agent, ctx)` directly. `until` / `max_attempts` / `tools` / `skills` overlays are ignored on the WorkerRunner path — the runner manages its own iteration and tool exposure.

### Custom Pydantic Output

```python
from pydantic import BaseModel
from bridgic.amphibious import ThinkCall

class Plan(BaseModel):
    phases: list[str]

class Planner(AmphibiousAutoma[CognitiveContext]):
    plan = think_unit(
        CognitiveWorker.inline("Create a plan.", output_schema=Plan),
        max_attempts=1,
    )

    async def on_agent(self, ctx):
        result = yield ThinkCall("plan")  # Returns a Plan instance via asend()
```

### Phase Annotation (snapshot)

```python
async def on_agent(self, ctx):
    async with self.snapshot(goal="Research phase"):
        yield ThinkCall("researcher")
    async with self.snapshot(goal="Writing phase"):
        yield ThinkCall("writer")
```

## Reference Files

- **Architecture details** (dispatcher layers, execution modes, exposure system, memory tiers, cognitive policies): See [references/architecture.md](references/architecture.md)
- **Complete API reference** (all classes, methods, parameters, types, yield primitives): See [references/api-reference.md](references/api-reference.md)
- **Full code patterns and examples** (all yield primitives, hooks, skills, tracing, filtering, etc.): See [references/patterns.md](references/patterns.md)
