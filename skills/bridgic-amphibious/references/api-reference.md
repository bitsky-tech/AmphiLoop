# Bridgic Amphibious API Reference

## Table of Contents
- [LLM Setup](#llm-setup)
- [Imports](#imports)
- [CLI Scaffolding](#cli-scaffolding)
- [AmphibiousAutoma](#amphibiousautoma)
- [CognitiveWorker](#cognitiveworker)
- [WorkerRunner Protocol](#workerrunner-protocol)
- [think_unit](#think_unit)
- [Yield Primitives](#yield-primitives)
- [Human-in-the-Loop](#human-in-the-loop)
- [Built-in Tools](#built-in-tools)
- [CognitiveContext](#cognitivecontext)
- [Context and Exposure](#context-and-exposure)
- [Data Models](#data-models)
- [Tool Definition](#tool-definition)
- [AgentTrace](#agenttrace)

---

## LLM Setup

Amphibious agents accept a `BaseLlm` instance from one of the bridgic LLM provider packages. The LLM is required for `AGENT` and `AMPHIFLOW` modes; pure `WORKFLOW` mode (where `on_workflow` is the only overridden template method) can run without one. Install one of the provider packages:

```python
# OpenAI (GPT-4, GPT-4o, etc.)
from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration

llm = OpenAILlm(
    api_key="your-api-key",
    api_base=None,                    # Optional: custom base URL
    timeout=120,                      # Optional: request timeout
    configuration=OpenAIConfiguration(
        model="gpt-4o",
        temperature=0.0,
        max_tokens=16384,
    ),
)

# OpenAI-compatible APIs (third-party providers)
from bridgic.llms.openai_like import OpenAILikeLlm, OpenAILikeConfiguration

llm = OpenAILikeLlm(
    api_base="https://api.provider.com/v1",  # Required
    api_key="provider-api-key",               # Required
    configuration=OpenAILikeConfiguration(model="model-name"),
)

# Self-hosted vLLM
from bridgic.llms.vllm import VllmServerLlm, VllmServerConfiguration

llm = VllmServerLlm(
    api_base="http://localhost:8000/v1",  # Required
    api_key="vllm-key",                    # Required
    configuration=VllmServerConfiguration(model="meta-llama/Llama-2-70b"),
)
```

Configuration class parameters (shared across providers): `model`, `temperature`, `top_p`, `presence_penalty`, `frequency_penalty`, `max_tokens`, `stop`.

## Imports

```python
from bridgic.amphibious import (
    # Orchestration
    AmphibiousAutoma, think_unit, ThinkUnitDescriptor, AgentTrace,
    # Worker
    CognitiveWorker, _DELEGATE,
    # External worker runtime
    WorkerRunner,
    # Context
    CognitiveContext, CognitiveHistory, CognitiveTools, CognitiveSkills,
    Context, Exposure, LayeredExposure, EntireExposure,
    # Yield primitives (scope rules apply — see Yield Primitives section)
    ActionCall, HumanCall, LLMCall, AgentCall, ThinkCall, RETURN,
    # Human channel decorator
    human_channel,
    # Data models
    Step, Skill, RunMode, ErrorStrategy,
    ActionResult, ActionStepResult, ToolResult,
    # Trace
    TraceStep, RecordedToolCall, StepOutputType,
    # Built-in tool specs (auto-injected; importable for explicit reuse)
    request_human_tool, bash_tool,
    read_file_tool, write_file_tool, edit_file_tool,
    glob_tool, grep_tool,
)
from bridgic.amphibious.builtin_tools import ALL_BUILTIN_TOOLS, current_agent
from bridgic.core.agentic.tool_specs import FunctionToolSpec
from bridgic.core.model.types import Message
```

## CLI Scaffolding

Bootstrap a new amphibious project:

```bash
bridgic-amphibious create [--base-dir <path>] [--task <description>]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--base-dir` | Current directory | Target directory for the generated file |
| `--task` | (omitted) | Injected as a top-level `# Task: ...` comment in `amphi.py` |

Generated file:

```
amphi.py    # AmphibiousAutoma stub: AmphiContext + Amphi class with think_unit, on_agent (yield ThinkCall), on_workflow (yield ActionCall / HumanCall / LLMCall / AgentCall / RETURN)
```

The scaffold writes only this single file in the target directory. It does not create subdirectories and does not emit runtime configuration (e.g. `.env`) — those concerns belong to the caller's environment, not the scaffold.

Python API: `create_project(base_dir: Optional[str] = None, task: Optional[str] = None) -> Path`. Raises `FileExistsError` if `amphi.py` already exists in the target directory.

## AmphibiousAutoma

```python
class AmphibiousAutoma(Generic[CognitiveContextT]):
```

Base class for dual-mode agents. Subclass with a generic `CognitiveContext` type parameter.

### Constructor

```python
AmphibiousAutoma(
    llm: Optional[BaseLlm] = None,  # Optional. Required for AGENT/AMPHIFLOW modes
    name: str = None,                # Optional agent name
    verbose: bool = False,           # Enable execution logging
)
```

### Class Attributes (Override in Subclasses)

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `builtin_tools` | `Optional[FrozenSet[str]]` | `None` | Filter for which entries of [`ALL_BUILTIN_TOOLS`](#built-in-tools) to auto-inject during `arun()`. `None` injects all; a frozenset of names restricts to that subset; `frozenset()` opts out entirely. The runtime `arun(builtin_tools=...)` kwarg wins over this attribute. Unknown names raise `ValueError` at `arun()` entry. |
| `WORKFLOW_STEP_FALLBACK_MAX_ATTEMPTS` | `int` | `5` | Max think-unit attempts when a workflow step falls back to agent mode for per-step recovery. |
| `_human_channels` | `ClassVar[Dict[str, str]]` | `{}` | **Auto-populated** by `__init_subclass__` from `@human_channel`-decorated methods. Maps channel-name → method-name. Subclass overrides win over parent declarations. Do not assign directly — use the `@human_channel` decorator. |

### arun() — Main Entry Point

```python
await agent.arun(
    # Context: either pre-built or auto-created
    context: CognitiveContextT = None,  # Pre-built context
    goal: str = "",                      # Auto-create: goal
    tools: List[ToolSpec] = [],          # Auto-create: tools
    skills: List[Skill] = [],            # Auto-create: skills
    cognitive_history: CognitiveHistory = None,  # Auto-create: custom history

    # Execution control
    mode: RunMode = RunMode.AUTO,
    trace_running: bool = False,
    max_consecutive_fallbacks: int = 1,
    builtin_tools: Optional[Iterable[str]] = None,  # Override class-level builtin_tools filter
) -> str
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `context` | `CognitiveContextT` | Current context after `arun()` |
| `final_answer` | `Optional[str]` | Captured from `RETURN(value)` in a top-level template method, or auto-captured from the finishing step's `step_content` if the generator exhausts without `RETURN`. |
| `llm` | `Optional[BaseLlm]` | The agent's LLM (`None` is allowed for pure WORKFLOW mode) |
| `spent_tokens` | `int` | Token usage for last `arun()` |
| `spent_time` | `float` | Time in seconds for last `arun()` |

### Template Methods (Override in Subclasses)

A subclass must override at least one of `on_agent` and `on_workflow`. Under
`RunMode.AUTO` the runtime picks the mode from which methods are overridden:
agent-only → `AGENT`, workflow-only → `WORKFLOW`, both → `AMPHIFLOW`.

All template methods may be written as **async generators** that yield framework primitives (the idiomatic form), OR as plain async coroutines. The dispatcher detects which form via `inspect.isasyncgen` and drives accordingly. The yield form is the public surface — async-generator hooks can use `RETURN(value)` to override the hook's return, and can yield other primitives (`ActionCall`, `LLMCall`, …) inside the hook body.

```python
# LLM-driven orchestration — yield ThinkCall to invoke named think_units.
# Allowed yields: ThinkCall, ActionCall, HumanCall, LLMCall, RETURN.
async def on_agent(self, ctx: CognitiveContextT) -> AsyncGenerator: ...

# Deterministic workflow — yield ActionCall etc. for tool execution.
# Allowed yields: ActionCall, HumanCall, LLMCall, AgentCall, RETURN.
async def on_workflow(self, ctx: CognitiveContextT) -> AsyncGenerator: ...

# Hooks (hook scope: ActionCall / HumanCall / LLMCall / RETURN allowed).
async def observation(self, ctx) -> AsyncGenerator: ...
async def before_action(self, decision_result, ctx) -> AsyncGenerator: ...
async def after_action(self, step_result, ctx) -> AsyncGenerator: ...
async def action_tool_call(self, tool_list, ctx) -> ActionResult: ...   # plain coroutine
async def action_custom_output(self, decision_result, ctx) -> Any: ...   # plain coroutine
```

### Hook Return Values via `RETURN`

`observation` and `before_action` are async generators; their "return value" is communicated via `yield RETURN(value)`:

| Hook | Effect of `yield RETURN(value)` |
|------|--------------------------------|
| `observation` | `value` becomes `ctx.observation` (string, optional). Exhausting without `RETURN` → observation = `None`. |
| `before_action` | `value` overrides the decision (e.g. filtered tool list). Exhausting without `RETURN` → original decision passes through unchanged. |
| `after_action` | `RETURN` is unused here; this hook's return value is ignored by the framework. |
| `on_agent` / `on_workflow` | `value` is written to `agent.final_answer`, overriding the auto-captured value. |

### Human Channel Decorator

```python
from bridgic.amphibious import human_channel

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    @human_channel              # bare form → channel name = method name
    async def terminal(self, prompt: str) -> str:
        return input(f"> {prompt} ")

    @human_channel("feishu")    # explicit channel name
    async def ask_feishu(self, prompt: str) -> str:
        return await feishu_client.send_and_wait(prompt)
```

`@human_channel` is the only public way to register human-input handlers — they are populated into `cls._human_channels` by `__init_subclass__` walking the MRO. Channel handlers are **plain async methods returning `str`**, not generators (they are leaf I/O operations).

### Utility Methods

```python
# Phase scoping — recursive snapshot/restore of context fields.
async with self.snapshot(goal="Sub-goal", **fields):
    yield ThinkCall("worker")
```

To set the final answer explicitly: `yield RETURN(value)` from the top-level template method generator.

## CognitiveWorker

```python
class CognitiveWorker:
```

Pure thinking unit — decides *what to do*, never *how*.

### Constructor

```python
CognitiveWorker(
    llm: BaseLlm = None,
    enable_rehearsal: bool = False,
    enable_reflection: bool = False,
    verbose: bool = None,
    verbose_prompt: bool = None,
    output_schema: Type[BaseModel] = None,  # Typed output mode
)
```

### Factory Methods

```python
# Quick creation from prompt string
worker = CognitiveWorker.inline(
    "Plan ONE immediate next step",
    llm=None,                          # Usually injected by agent
    enable_rehearsal=False,
    enable_reflection=False,
    output_schema=None,                # Set for typed output
    verbose=None,
    verbose_prompt=None,
)

# Alias
worker = CognitiveWorker.from_prompt("...")
```

### Template Methods (Override in Subclasses)

```python
# Required: Define thinking prompt
async def thinking(self) -> str: ...

# Optional hooks
async def observation(self, context) -> Any: ...           # Return _DELEGATE or str
async def build_messages(self, think_prompt, tools_description,
                         output_instructions, context_info) -> List[Message]: ...
async def before_action(self, decision_result, context) -> Any: ...
async def after_action(self, step_result, ctx) -> Any: ...
```

### Class Attribute

```python
output_schema: Optional[Type[BaseModel]] = None
# When set, worker produces a typed Pydantic instance.
# Skips tool-call loop. Acquiring policy disabled.
# yield ThinkCall("name") returns the typed instance via asend().
```

## WorkerRunner Protocol

```python
from bridgic.amphibious import WorkerRunner

@runtime_checkable
class WorkerRunner(Protocol):
    async def run(self, agent: "AmphibiousAutoma", ctx: "CognitiveContext") -> None: ...
```

A minimal alternative to `CognitiveWorker` for plug-in *external* agent runtimes (Claude Code, OpenAI Agents, bespoke ReAct stacks, …) that already have their own internal loop. The dispatcher checks `isinstance(worker, CognitiveWorker)` first; if False but the worker satisfies `WorkerRunner`, it calls `run(agent, ctx)` directly and skips the observe-think-act cycle.

```python
class ClaudeCodeRunner:
    async def run(self, agent, ctx):
        # subprocess out to claude, feed it ctx.goal, write the
        # transcript into ctx.cognitive_history (so the framework
        # sees it through the standard history surface).
        ...

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    external_think = think_unit(ClaudeCodeRunner())

    async def on_agent(self, ctx):
        yield ThinkCall("external_think")
```

`until` / `max_attempts` / `tools` / `skills` overlays from `think_unit(...)` (or the `ThinkCall(...)` overlay) are **ignored** on the WorkerRunner path — the runner manages its own loop and tool exposure. `CognitiveWorker` does **not** itself satisfy `WorkerRunner`; the two paths are kept distinct so the `isinstance` check is unambiguous.

## think_unit

```python
think_unit(
    worker: CognitiveWorker | WorkerRunner,
    *,
    max_attempts: int = 1,
    until: Callable = None,            # Loop condition (CognitiveWorker only)
    tools: List[str] = None,           # Tool name filter (CognitiveWorker only)
    skills: List[str] = None,          # Skill name filter (CognitiveWorker only)
    on_error: ErrorStrategy = ErrorStrategy.RAISE,
    max_retries: int = 0,              # For RETRY strategy
) -> ThinkUnitDescriptor
```

Use as class variable:

```python
class MyAgent(AmphibiousAutoma[CognitiveContext]):
    planner = think_unit(CognitiveWorker.inline("Plan step"), max_attempts=5)

    async def on_agent(self, ctx):
        yield ThinkCall("planner")                          # Single execution
        yield ThinkCall("planner", until=lambda c: c.done)   # Loop until condition
        yield ThinkCall(                                     # With overrides
            "planner",
            until=lambda c: c.done,
            max_attempts=50,
            tools=["search"],
        )
```

### ThinkCall overrides

`ThinkCall(name, ...)` accepts the same overlay parameters as `think_unit(...)`. Any field set to `None` on the ThinkCall falls back to the descriptor's value. Fields available: `until`, `max_attempts`, `tools`, `skills`.

```python
@dataclass(frozen=True)
class ThinkCall:
    name: str
    until: Optional[Callable[..., Union[bool, Awaitable[bool]]]] = None
    max_attempts: Optional[int] = None
    tools: Optional[List[str]] = None
    skills: Optional[List[str]] = None
```

The result of `result = yield ThinkCall(...)` is the worker's typed output if `output_schema` is set, otherwise `None`.

## Yield Primitives

Six primitives, each with a strict scope. The dispatcher routes each yield to its handler and sends the result back via `asend()`. Scope violations raise `RuntimeError` at dispatch time.

| Primitive | `on_workflow` | `on_agent` | hooks |
|-----------|:-------------:|:----------:|:-----:|
| `ActionCall` | ✓ | ✓ | ✓ |
| `HumanCall` | ✓ | ✓ | ✓ |
| `LLMCall` | ✓ | ✓ | ✓ |
| `AgentCall` | ✓ | ✗ | ✗ |
| `ThinkCall` | ✗ | ✓ | ✗ |
| `RETURN` | ✓ | ✓ | ✓ |

### ActionCall — Deterministic tool execution

```python
from bridgic.amphibious import ActionCall

# Any flow:
result = yield ActionCall("tool_name", arg1="value", arg2=123)
# result: List[ToolResult]
```

```python
@dataclass(init=False)
class ActionCall:
    tool_name: str
    description: str
    worker: Optional[Any]        # Optional CognitiveWorker for step-level fallback in AMPHIFLOW
    tool_args: Dict[str, Any]

    def __init__(self, tool_name: str, *, description: str = "", worker=None, **tool_args): ...
```

### HumanCall — Pause for human input

```python
from bridgic.amphibious import HumanCall

# Any flow:
feedback = yield HumanCall(prompt="Confirm this action?")              # implicit default channel
feedback = yield HumanCall(prompt="Confirm?", channel="feishu")        # explicit channel
# feedback: str
```

```python
@dataclass
class HumanCall:
    prompt: str = ""
    channel: Optional[str] = None  # None → implicit-default resolution; see Human-in-the-Loop below
```

Per-call timeouts are not exposed; if needed, the channel handler should enforce its own timeout.

### LLMCall — Direct LLM invocation

```python
from bridgic.amphibious import LLMCall
from bridgic.core.model.protocols import PydanticModel

# Any flow:
text   = yield LLMCall.chat("What is 2+2?")
parsed = yield LLMCall.structure_output("Extract...", constraint=PydanticModel(model=Schema))
calls, reply = yield LLMCall.tool_selector("...", tools=[...])
```

Three protocols, three return types via `asend()`:

| Protocol | Class method | Returns via `asend()` |
|----------|--------------|------------------------|
| `chat` | `LLMCall.chat(prompt, *, history=None)` | `str` (the message content) |
| `structure_output` | `LLMCall.structure_output(prompt, *, constraint, history=None)` | the typed instance from `StructuredOutput.astructured_output()` |
| `tool_selector` | `LLMCall.tool_selector(prompt, *, tools, history=None)` | `Tuple[List[ToolCall], Optional[str]]` |

`prompt` is appended as the final `Role.USER` message; `history` (if supplied) is prepended verbatim before the prompt. Per-call `temperature` / `**kwargs` overrides are deliberately not exposed — those are baked at LLM construction time.

```python
@dataclass(frozen=True)
class LLMCall:
    protocol: Literal["chat", "structure_output", "tool_selector"]
    prompt: str = ""
    history: Optional[List[Message]] = None
    constraint: Optional[Constraint] = None       # required iff protocol == "structure_output"
    tools: Optional[List[Tool]] = None            # required iff protocol == "tool_selector"
```

### AgentCall — Sub-agent with context scope (`on_workflow` only)

```python
from bridgic.amphibious import AgentCall

# Only valid in on_workflow:
yield AgentCall(goal="Handle the login popup")
yield AgentCall(goal="Pick a flight", tools=["search_flights", "book"])
yield AgentCall(goal="Summarize", history=prior_messages, skills=["summary"])
```

```python
@dataclass
class AgentCall:
    goal: str = ""
    history: Optional[Any] = None       # Optional[CognitiveHistory]; None → fresh CognitiveHistory()
    tools: Optional[List[str]] = None   # Tool-name filter applied to ctx.tools for the sub-agent
    skills: Optional[List[str]] = None  # Skill-name filter applied to ctx.skills for the sub-agent
```

`AgentCall` snapshots the context (fresh `goal`, optional `history` / `tools` / `skills` filters) and recursively re-enters `on_agent` to handle the sub-task. It scopes the sub-agent's *context* — it does not control *how it thinks*. For a single named cognitive step, declare a `think_unit` and `yield ThinkCall("name")` from inside `on_agent` instead.

Requires the agent class to override `on_agent`; raises `RuntimeError` at dispatch time otherwise. Yielding `AgentCall` from `on_agent` or any hook raises `RuntimeError("AgentCall is only valid inside on_workflow…")`.

### ThinkCall — Invoke a named think_unit (`on_agent` only)

```python
from bridgic.amphibious import ThinkCall

# Only valid in on_agent:
result = yield ThinkCall("main_think")
result = yield ThinkCall("exec_think", until=lambda c: c.done, max_attempts=20)
```

`name` resolves via `getattr(type(self), name)` — must point to a `ThinkUnitDescriptor`. Yielding `ThinkCall` from `on_workflow` or any hook raises `RuntimeError("ThinkCall is only valid inside on_agent…")`.

### RETURN — Emit a return value from an async generator

```python
from bridgic.amphibious import RETURN

# Any flow:
async def on_agent(self, ctx):
    yield ThinkCall("main_think")
    yield RETURN(ctx.cognitive_history.get_all()[-1].content)

# In a hook:
async def observation(self, ctx):
    snapshot = yield ActionCall("bash", command="bridgic-browser snapshot")
    yield RETURN(snapshot[0].result)
```

```python
@dataclass(frozen=True)
class RETURN:
    value: Any = None
```

PEP 525 forbids `return value` inside async generators (only bare `return` is allowed). `RETURN(value)` is the framework-level workaround: when the dispatcher receives it, it captures `RETURN.value`, immediately closes the generator, and returns the value to its caller. **Anything yielded after a `RETURN` is unreachable.** For top-level template-method generators, the captured value is written to `agent.final_answer` (overriding the auto-capture from history).

## Human-in-the-Loop

Three entry points all converge on the same `_dispatch_human_channel` resolver:

| Entry Point | Where | Usage |
|-------------|-------|-------|
| `yield HumanCall(prompt=..., channel=...)` | Any flow (`on_agent`, `on_workflow`, hooks) | `feedback = yield HumanCall(prompt="...")` |
| `request_human` tool | LLM tool-call, any mode | Auto-injected into `context.tools`; no setup needed |
| `agent._dispatch_human_channel(prompt, channel=None)` | Internal helper | Used by both of the above; rarely called directly |

### Channel resolution rules

`HumanCall(channel=None)` resolves to a registered handler at dispatch time:

1. **Zero `@human_channel` handlers registered** → fall through to a built-in stdin handler (`_stdin_human_fallback`, reads a line from stdin via `run_in_executor`).
2. **One handler registered** → it is the implicit default.
3. **Multiple handlers registered** → raise `RuntimeError("HumanCall(channel=None) is ambiguous: N channels registered…")`. The caller (or the LLM via `request_human`) must pass `channel="name"` explicitly.

`HumanCall(channel="name")` looks up the handler in `cls._human_channels` (built by `__init_subclass__` from `@human_channel`-decorated methods on the class and its MRO ancestors). An unknown name raises `RuntimeError("Unknown human channel: ...")`.

### Registering a channel

```python
from bridgic.amphibious import human_channel

class MyAgent(AmphibiousAutoma[CognitiveContext]):
    @human_channel              # bare → channel name = "terminal"
    async def terminal(self, prompt: str) -> str:
        return input(f"\n> {prompt}\n")

    @human_channel("feishu")    # explicit channel name
    async def ask_feishu(self, prompt: str) -> str:
        return await feishu_client.send_and_wait(prompt)
```

Channel handlers are plain async methods returning `str` — they are *not* async generators (they are leaf I/O operations and do not dispatch inner yields).

### `request_human` as a built-in tool

`request_human` is one of the seven [built-in tools](#built-in-tools) auto-injected into `context.tools` during `arun()`, so the LLM can call it in any mode (AGENT, WORKFLOW fallback, AMPHIFLOW) without you wiring it through `tools=[...]`:

```python
await agent.arun(goal="Plan a trip, ask me if you need confirmation.", tools=[search_tool])
```

Internally, the tool routes through `agent._dispatch_human_channel(prompt, channel=None)` — the same path as `HumanCall(channel=None)`. So if you have multiple `@human_channel` handlers registered, the LLM-facing `request_human` tool needs at least one of them to be the unambiguous default (otherwise `request_human` will raise at call time).

The tool resolves the running agent through `current_agent` (a `contextvars.ContextVar`), so each concurrent `arun()` task gets its own binding and parallel agents do not interfere. Passing `request_human_tool` explicitly via `tools=[...]` is harmless — the injection step deduplicates by tool name.

## Built-in Tools

Seven `FunctionToolSpec` instances are auto-injected into every `AmphibiousAutoma` agent's `context.tools` during `arun()`, subject to the [`builtin_tools` filter](#class-attributes-override-in-subclasses). They are exported from both `bridgic.amphibious` and `bridgic.amphibious.builtin_tools` as `*_tool` constants.

```python
from bridgic.amphibious.builtin_tools import ALL_BUILTIN_TOOLS, current_agent
# ALL_BUILTIN_TOOLS: tuple of all seven specs in display order.
# current_agent:    ContextVar bound to the running AmphibiousAutoma during arun().
```

**Error contract.** Tools raise on validation failures. The framework's per-tool exception handler (`_action_tool_call._run_one`) catches every exception and produces:

```python
ActionStepResult(success=False, error=str(exc), tool_result=None)
```

— so the LLM sees the error in the next observation, and `on_workflow` (without fallback) propagates it as `RuntimeError("Tool execution failed for: ...")`. Tools never wrap errors as `<error>...</error>` strings at their own layer.

### request_human

```python
async def request_human(prompt: str) -> str
```

Pause and ask the human operator a question. Internally calls `agent._dispatch_human_channel(prompt, channel=None)` — the same code path used by `HumanCall(channel=None)`. See [Human-in-the-Loop](#human-in-the-loop) for the channel resolution story.

### bash

```python
async def bash(command: str, timeout: int = 120000, cwd: str = "") -> str
```

Execute a shell command via the user's default shell. Returns a tagged envelope:

```
<stdout>
...captured stdout...
</stdout>
<stderr>
...captured stderr...
</stderr>
<exit_code>0</exit_code>
```

| Param | Description |
|-------|-------------|
| `command` | Shell command. Multiple commands may be chained with `&&` / `\|\|` / `;`. |
| `timeout` | Milliseconds before the process is killed. Default 120000 (2 min); maximum 600000 (10 min). |
| `cwd` | Working directory. Empty string inherits the parent process's cwd. |

Stateless — does not depend on the running agent. Non-zero exit codes are NOT exceptions; they are reported via the envelope so the LLM can interpret them. Output past 30 KB is truncated with a marker.

Raises:
- `ValueError` if `command` is empty.
- `TimeoutError` if the command exceeds `timeout` (process killed and awaited before the raise).

### read_file

```python
async def read_file(file_path: str, offset: int = 0, limit: int = 0) -> str
```

Read a file's contents in `cat -n` format (line number + tab + content). The line-numbered output is the format that `edit_file` expects you to base its `old_string` on (line numbers excluded — only the actual content matches).

Calling `read_file` records the file's mtime on the agent's per-run `_read_tracker` dict; `write_file` and `edit_file` consult it to enforce the read-before-modify invariant.

| Param | Description |
|-------|-------------|
| `file_path` | Absolute path. Relative paths are rejected. |
| `offset` | 1-based line number to start from. `0` means the first line. |
| `limit` | Max lines to return. `0` means the default cap of 2000 lines. |

Maximum file size is 5 MB. Lines longer than 2000 chars are truncated with a marker. Empty files and offsets past the end return informational text rather than empty strings or exceptions.

Raises:
- `ValueError` if `file_path` is empty / not absolute / not a regular file / file too large.
- `FileNotFoundError` if the file does not exist.

### write_file

```python
async def write_file(file_path: str, content: str) -> str
```

Create a new file or overwrite an existing one. Creating new files has no preconditions; overwriting an existing file requires that `read_file` was called on the path AND the file has not changed externally since that read.

Raises:
- `ValueError` if `file_path` is empty / not absolute / target exists but is not a regular file.
- `FileNotFoundError` if the parent directory does not exist.
- `RuntimeError` if the file exists and was not read first, or has been modified externally since the read.

### edit_file

```python
async def edit_file(
    file_path: str,
    old_string: str,
    new_string: str,
    replace_all: bool = False,
) -> str
```

Replace `old_string` with `new_string`. By default `old_string` must occur exactly once — supply more surrounding context if it doesn't, or pass `replace_all=True` for rename refactors. Enforces the read-before-modify invariant.

Raises:
- `ValueError` if `file_path` is invalid / `old_string` is empty / equals `new_string` / not found / occurs multiple times without `replace_all`.
- `FileNotFoundError` if the file does not exist.
- `RuntimeError` if the file has not been read first or was modified externally since the read.

### glob

```python
async def glob(pattern: str, path: str = "") -> str
```

Find files matching a glob pattern (e.g. `**/*.py`, `src/**/*.ts`). Returns matching paths sorted by mtime descending, so recently-touched files surface first.

| Param | Description |
|-------|-------------|
| `pattern` | Glob pattern relative to `path`. |
| `path` | Absolute search root. Empty string means the process's cwd. |

Capped at 100 results; "no match" returns informational text.

Raises:
- `ValueError` for empty `pattern` or non-absolute `path`.
- `NotADirectoryError` if `path` is not a directory.

### grep

```python
async def grep(
    pattern: str,
    path: str = "",
    glob: str = "",
    output_mode: str = "files_with_matches",
    case_insensitive: bool = False,
    head_limit: int = 0,
) -> str
```

Regex content search across files. Pure-Python via the standard `re` module — not a ripgrep replacement.

| Param | Description |
|-------|-------------|
| `pattern` | Python regex. |
| `path` | Absolute search root; empty = cwd. |
| `glob` | Optional glob filter on file paths (e.g. `*.py`). Empty = scan all files recursively. |
| `output_mode` | `"files_with_matches"` (default), `"count"` (`path:N`), or `"content"` (`path:lineno:line`). |
| `case_insensitive` | If True, match case-insensitively. |
| `head_limit` | Max result lines. `0` = default cap of 200. |

Hidden directories (path components starting with `.`) are skipped — keeps `.git`, `.venv` and similar metadata trees out of results. Capped at 5000 files scanned.

Raises:
- `ValueError` for empty `pattern`, non-absolute `path`, or unknown `output_mode`.
- `NotADirectoryError` if `path` is not a directory.
- `re.error` on invalid regex.

### Filter resolution

`AmphibiousAutoma.arun()` resolves which built-ins to inject in this order:

1. `arun(builtin_tools=...)` runtime kwarg, if provided.
2. Otherwise the class-level `builtin_tools` attribute.
3. Otherwise `None`, which means "inject every entry of `ALL_BUILTIN_TOOLS`".

A non-`None` resolution must reference only valid tool names; unknown entries (typos, stale references) raise `ValueError` at `arun()` entry. The selected set is intersected with already-present `context.tools` by `tool_name` — user-supplied tools win, the colliding built-in is silently skipped.

### Read-before-modify tracker

`AmphibiousAutoma._read_tracker: Dict[str, float]` maps absolute path → mtime at last successful `read_file`. It is reset at every `arun()` entry (so the invariant is scoped to a single run) and accessed by the filesystem tools through `current_agent`. `track_read` is a best-effort hook — a failed `os.stat` after a successful read is silently swallowed; the tracker simply has no entry, which causes a subsequent `edit_file` / `write_file` to correctly demand a re-read.

## CognitiveContext

```python
class CognitiveContext(Context):
```

Default context combining goal, tools, skills, and history.

### Fields

| Field | Type | Exposure | Description |
|-------|------|----------|-------------|
| `goal` | `str` | Plain | The goal to achieve |
| `tools` | `CognitiveTools` | EntireExposure | Available tools |
| `skills` | `CognitiveSkills` | LayeredExposure | Available skills |
| `cognitive_history` | `CognitiveHistory` | LayeredExposure | Execution history |
| `observation` | `Optional[str]` | Hidden (`display=False`) | Current observation |

### Custom Context

```python
from pydantic import Field, ConfigDict

class MyContext(CognitiveContext):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    current_page: str = Field(default="", description="Current page URL")
    extracted_data: dict = Field(
        default_factory=dict,
        json_schema_extra={"display": False}  # Hidden from LLM
    )
```

### CognitiveHistory Configuration

```python
CognitiveHistory(
    working_memory_size: int = 5,    # Recent steps with full details
    short_term_size: int = 20,       # Older steps as summaries
    compress_threshold: int = 10,    # Trigger LLM compression
)
```

### CognitiveSkills Methods

```python
skills = CognitiveSkills()
skills.add(Skill(name="...", description="...", content="..."))
skills.add_from_file("path/to/SKILL.md")
skills.add_from_markdown("---\nname: ...\n---\nContent")
skills.load_from_directory("skills/")
```

## Context and Exposure

### Context Base Class Methods

```python
ctx.summary() -> Dict[str, str]               # All field summaries
ctx.format_summary(include=None, exclude=None) -> str  # Formatted string
ctx.get_details(field: str, idx: int) -> Optional[str]  # LayeredExposure detail
ctx.get_field(field: str) -> Tuple[Optional[List[str]], Any]
ctx.get_revealed_items() -> List[Tuple[str, int]]
ctx.reset_revealed() -> None
ctx.set_llm(llm) -> None                      # Propagate LLM to Exposure fields
```

### Creating Custom Exposure Fields

```python
class MyExposure(LayeredExposure[MyItem]):
    def summary(self) -> List[str]: ...
    def get_details(self, index: int) -> Optional[str]: ...

class MyContext(CognitiveContext):
    my_field: MyExposure = Field(default_factory=MyExposure)
```

## Data Models

### ErrorStrategy

```python
class ErrorStrategy(Enum):
    RAISE = "raise"    # Re-raise exceptions (default)
    IGNORE = "ignore"  # Silently skip failed cycles
    RETRY = "retry"    # Retry up to max_retries times
```

### RunMode

```python
class RunMode(str, Enum):
    AGENT = "agent"
    WORKFLOW = "workflow"
    AMPHIFLOW = "amphiflow"
    AUTO = "auto"
```

### Skill

```python
class Skill(BaseModel):
    name: str
    description: str = ""
    content: str = ""
    metadata: Dict[str, Any] = Field(default_factory=dict)
```

### Step

```python
class Step(BaseModel):
    content: str = ""
    result: Optional[Any] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)
    status: Optional[bool] = None
```

### ToolResult (returned by `yield ActionCall`)

```python
@dataclass
class ToolResult:
    tool_name: str
    tool_arguments: Dict[str, Any]
    result: Any
    success: bool = True
    error: Optional[str] = None
```

### ActionResult / ActionStepResult

```python
class ActionResult(BaseModel):
    results: List[ActionStepResult]

class ActionStepResult(BaseModel):
    tool_id: str
    tool_name: str
    tool_arguments: Dict[str, Any]
    tool_result: Any
    success: bool = True
    error: Optional[str] = None
```

## Tool Definition

```python
from bridgic.core.agentic.tool_specs import FunctionToolSpec

# From async function
async def my_tool(param1: str, param2: int) -> str:
    """Tool description visible to LLM."""
    return "result"

tool_spec = FunctionToolSpec.from_raw(my_tool)
```

## AgentTrace

```python
# Enable tracing
result = await agent.arun(..., trace_running=True)

# Access trace
trace = agent._agent_trace.build()
# Returns: {"phases": [...], "orphan_steps": [...], "metadata": {...}}
# phases: steps grouped by self.snapshot() blocks (empty if no phase annotations)
# orphan_steps: steps outside any phase annotation

# Save / Load
agent._agent_trace.save("trace.json")
loaded = AgentTrace.load("trace.json")  # Returns plain dict
```
