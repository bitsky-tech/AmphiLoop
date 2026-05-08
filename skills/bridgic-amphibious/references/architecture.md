# Bridgic Amphibious Architecture Reference

## Table of Contents
- [Four-Layer Architecture](#four-layer-architecture)
- [Yield-Based Template Methods](#yield-based-template-methods)
- [Three-Layer Dispatcher](#three-layer-dispatcher)
- [Yield Primitives & Scope Rules](#yield-primitives--scope-rules)
- [Observe-Think-Act (OTC) Cycle](#observe-think-act-otc-cycle)
- [Execution Modes (RunMode)](#execution-modes-runmode)
- [Data Exposure System](#data-exposure-system)
- [Cognitive Policies](#cognitive-policies)
- [Memory Architecture (CognitiveHistory)](#memory-architecture-cognitivehistory)
- [Think Unit Descriptor Pattern](#think-unit-descriptor-pattern)
- [WorkerRunner — External Runtime Path](#workerrunner--external-runtime-path)
- [Phase Annotation (snapshot)](#phase-annotation-snapshot)
- [Workflow Fallback Mechanism](#workflow-fallback-mechanism)
- [Built-in Tools Subsystem](#built-in-tools-subsystem)
- [Human-in-the-Loop](#human-in-the-loop)

---

## Four-Layer Architecture

```
Layer 4: AmphibiousAutoma (Orchestration)
  ├─ on_agent()    → async generator yielding ThinkCall / ActionCall / ...
  ├─ on_workflow() → async generator yielding ActionCall / AgentCall / ...
  └─ Three-layer dispatcher → drives the generator, routes each yield

Layer 3: CognitiveWorker (Think Unit) — primary worker type
  ├─ thinking()    → LLM decision logic
  └─ Policies      → acquiring, rehearsal, reflection
   plus
  WorkerRunner Protocol — escape hatch for external agent runtimes

Layer 2: CognitiveContext (State Management)
  ├─ goal, tools, skills, cognitive_history, observation
  └─ Exposure system → data visibility control

Layer 1: Exposure (Data Abstraction)
  ├─ LayeredExposure → progressive disclosure
  └─ EntireExposure  → full exposure
```

## Yield-Based Template Methods

All template methods (`on_agent`, `on_workflow`, `observation`, `before_action`, `after_action`) are **async generators** that yield framework primitives. The dispatcher drives the generator with `__anext__` / `asend`, routes each yielded primitive to its handler, and feeds the handler's result back via `asend()`.

```python
async def on_workflow(self, ctx):
    result_list = yield ActionCall("search", q="laptop")   # ← list[ToolResult] via asend()
    text = yield LLMCall.chat(f"Summarize: {result_list[0].result}")
    yield RETURN(text)                                     # ← captures and closes
```

PEP 525 forbids `return value` inside async generators (only bare `return` is allowed). The framework uses a yielded `RETURN(value)` primitive instead — the dispatcher captures `RETURN.value`, closes the generator, and uses the value as that flow's return.

## Three-Layer Dispatcher

The dispatcher is split into three methods, each with a single responsibility:

```
_dispatch_flow         (driver — body-mode policy)
   ├─ Drives the generator with __anext__ / asend
   ├─ Captures RETURN(value) and breaks the loop
   ├─ On generator-internal exception with can_fallback=True:
   │     escalate to on_agent via _invoke_template
   └─ Catches _FullFallback raised by _dispatch_call to escalate
                ↓ delegates each yielded item to ↓
_dispatch_call         (per-Call handler — scope validation + per-Call fallback)
   ├─ AgentCall   → must be scope='workflow';  recursively re-enter on_agent
   ├─ ThinkCall   → must be scope='agent';     run the named CognitiveWorker / WorkerRunner
   ├─ ActionCall  → run the tool; on failure escalate via _FullFallback if step threshold hit
   ├─ HumanCall   → resolve channel and call handler
   └─ LLMCall     → dispatch to chat / structure_output / tool_selector
                ↑ used by ↑
_invoke_template       (lightweight driver — for hooks, no fallback)
   └─ Drives a hook generator with __anext__ / asend, no _FullFallback handling
```

| Concept | What lives here |
|---------|-----------------|
| `scope: "workflow" \| "agent" \| "hook"` | Threaded as a parameter through all three layers, used by `_dispatch_call` to validate `AgentCall` / `ThinkCall` |
| `_FullFallback` | Internal sentinel exception. Raised by `_dispatch_call` to ask `_dispatch_flow` to escalate to `on_agent`. Not part of public API. |
| `_FlowState` | Mutable per-flow state (max_consecutive_fallbacks, consecutive_failures, step_index, failed_steps). Created fresh per `_dispatch_flow` invocation; `None` when called from `_invoke_template` (hooks have no fallback bookkeeping). |
| `can_fallback` | Bool, threaded along with `scope`. True only for `_amphiflow`'s on_workflow drive; False for pure WORKFLOW, hook drives, and AgentCall sub-drives. |

`_agent`, `_workflow`, `_amphiflow` are the three GraphAutoma entry points. Each delegates to `_dispatch_flow` with the appropriate `scope` and `can_fallback` settings.

## Yield Primitives & Scope Rules

Six primitives, with strict scope rules enforced by `_dispatch_call`:

| Primitive | `on_workflow` | `on_agent` | hooks | Result via `asend()` |
|-----------|:-------------:|:----------:|:-----:|----------------------|
| `ActionCall(name, **args)` | ✓ | ✓ | ✓ | `List[ToolResult]` |
| `HumanCall(prompt=..., channel=...)` | ✓ | ✓ | ✓ | `str` (the response) |
| `LLMCall.chat / .structure_output / .tool_selector(...)` | ✓ | ✓ | ✓ | `str` / typed instance / `(List[ToolCall], Optional[str])` |
| `AgentCall(goal=..., history=..., tools=..., skills=...)` | ✓ | ✗ | ✗ | `None` |
| `ThinkCall(name, ...)` | ✗ | ✓ | ✗ | typed instance (if `output_schema`) or `None` |
| `RETURN(value)` | ✓ | ✓ | ✓ | (closes the generator; not asend-able) |

A scope violation raises `RuntimeError` at dispatch time:

- `AgentCall` outside `on_workflow`: `AgentCall represents the deterministic→autonomous transition; once you are inside on_agent, keep thinking via ThinkCall instead.`
- `ThinkCall` outside `on_agent`: `ThinkCall is only valid inside on_agent (scope='agent')…`

Why these rules: they encode role distinctions without restricting expressiveness inside each scope. `on_agent` is the LLM-driven flow — running another `on_agent` from inside it would just be more thinking, so use `ThinkCall`. `on_workflow` is the deterministic flow — `AgentCall` is the explicit "step out into autonomous reasoning for this sub-task" move. Hooks run between steps and have no business spawning sub-agents or reentering the cognitive runtime.

## Observe-Think-Act (OTC) Cycle

Each `CognitiveWorker` execution (driven by `_run` / `_run_once`) follows:

1. **Observe**: Gather current state.
   - Worker `observation(ctx)` called first.
   - If returns `_DELEGATE` (or `None` from a stub override), delegates to agent-level `observation(ctx)` via `_invoke_template`.
   - Result stored in `ctx.observation`.

2. **Think**: LLM decides next action.
   - `CognitiveWorker._thinking(ctx)` runs the LLM.
   - Multi-round loop if cognitive policies fire (acquiring, rehearsal, reflection).
   - Returns decision with `step_content`, `finish`, `output`.

3. **Act**: Execute tools or produce structured output.
   - `before_action()` hooks (worker → agent delegation, `_invoke_template`-driven).
   - Route to `action_tool_call()` for tool calls.
   - Route to `action_custom_output()` for structured output (`output_schema` set).
   - `after_action()` hooks (worker → agent delegation).
   - Record result in `CognitiveHistory`.

The OTC cycle is the **CognitiveWorker** path. The alternative path — `WorkerRunner` — bypasses the cycle entirely (see below).

## Execution Modes (RunMode)

| Mode | Driver | Best For | Fallback |
|------|--------|----------|----------|
| `AGENT` | LLM (`on_agent`) | Open-ended, adaptive tasks | N/A |
| `WORKFLOW` | Code (`on_workflow`) | Known, repeatable processes | N/A |
| `AMPHIFLOW` | Workflow + LLM fallback | Robust hybrid execution | Automatic |
| `AUTO` (default) | Auto-detect from overridden methods | Most subclasses | Inherits from resolved mode |

- `AUTO` resolution rules:
  - only `on_agent` overridden → `AGENT`
  - only `on_workflow` overridden → `WORKFLOW`
  - both overridden → `AMPHIFLOW`
  - neither overridden → `RuntimeError` at run time
- LLM requirement: `AGENT` and `AMPHIFLOW` require an LLM at `arun()` time; pure `WORKFLOW` does not.

## Data Exposure System

Controls how context data is visible to the LLM.

### EntireExposure[T]

All data visible at once. Used for tools.

- Methods: `summary()` only.
- Implementation: `CognitiveTools`.

### LayeredExposure[T]

Progressive disclosure with details on demand.

- Methods: `summary()` + `get_details(index)` + `reveal(index)`.
- Caching: `_revealed` dict stores cached details.
- Reset: `reset_revealed()` clears cache (at phase boundaries).
- Implementations: `CognitiveSkills`, `CognitiveHistory`.

### Context Field Detection

`Context` base class auto-detects `Exposure`-typed fields and classifies them as `layered` or `entire`. Custom fields that are plain types (str, dict, etc.) appear directly in the summary.

- Hide a field from summary: `json_schema_extra={"display": False}`.
- Enable LLM propagation to an Exposure field: `json_schema_extra={"use_llm": True}`.

## Cognitive Policies

Multi-round thinking within a single OTC cycle. Each policy fires **at most once**, then closes.

### Acquiring (built-in, always active when no `output_schema`)

LLM requests details from `LayeredExposure` fields (skills, cognitive_history).

```
LLM fills: details: [{field: "skills", index: 0}]
→ Framework reveals full content
→ Re-think with revealed data
```

### Rehearsal (opt-in: `enable_rehearsal=True`)

LLM mentally simulates planned action.

```
LLM fills: rehearsal: "If I call search_tool, I expect..."
→ Prediction injected as context
→ Re-think with simulation
```

### Reflection (opt-in: `enable_reflection=True`)

LLM assesses information quality.

```
LLM fills: reflection: "The data is inconsistent because..."
→ Assessment injected as context
→ Re-think with assessment
```

Policy execution order: **Acquiring → Rehearsal → Reflection**. After all active policies fire, LLM must commit to a final action.

## Memory Architecture (CognitiveHistory)

Four-tier layered memory with automatic compression:

```
New step added
    │
    v
[Working Memory]    ← latest N steps, full details shown
    │
    v (overflow)
[Short-term Memory] ← next M steps, summaries only, queryable via Acquiring
    │
    v (overflow, triggers compression)
[Long-term Pending] ← brief summaries, awaiting batch compression
    │
    v (compress_threshold reached + LLM available)
[Long-term Compressed] ← LLM-compressed concise paragraph
```

Default parameters:
- `working_memory_size=5`
- `short_term_size=20`
- `compress_threshold=10`

## Think Unit Descriptor Pattern

Think units use Python descriptors for class-level declaration:

1. `think_unit(...)` factory returns a `ThinkUnitDescriptor`.
2. Both class- and instance-level access (`MyAgent.main_think`, `self.main_think`) return the descriptor itself — invocation goes through `yield ThinkCall("name")`.
3. The dispatcher resolves the name via `getattr(type(self), name)`, picks up the descriptor, and:
   - For a `CognitiveWorker` template: clones the worker for state isolation, injects the agent's LLM at runtime, and runs the OTC cycle through `_run`.
   - For a `WorkerRunner` template: uses the template directly (the runner manages its own state) and calls `run(agent, ctx)` once.
4. Overlay parameters from `think_unit(...)` (descriptor defaults) and from `ThinkCall(name, ...)` (per-yield overrides) merge: `None` on the ThinkCall keeps the descriptor's value, anything else overrides.

## WorkerRunner — External Runtime Path

`CognitiveWorker` decomposes execution into the explicit observe-think-act cycle the framework drives. That's convenient when you want the framework to manage iteration, tool selection, and trace recording — and rigid when the goal is to plug in an *external* agent runtime that already has its own internal loop.

`WorkerRunner` is the minimal alternative — a `@runtime_checkable` Protocol with a single method:

```python
@runtime_checkable
class WorkerRunner(Protocol):
    async def run(self, agent: AmphibiousAutoma, ctx: CognitiveContext) -> None: ...
```

The dispatcher checks `isinstance(worker, CognitiveWorker)` first; if False but `isinstance(worker, WorkerRunner)`, it calls `run(agent, ctx)` directly and skips the OTC cycle.

```
ThinkCall("name") yielded
    │
    v
_dispatch_call resolves descriptor and worker template
    │
    ├── CognitiveWorker?         → clone + inject LLM + drive OTC cycle through _run
    │
    └── WorkerRunner (Protocol)? → call run(agent, ctx) once; runner owns its loop
```

**Tradeoffs.** On the WorkerRunner path, the `until` / `max_attempts` / `tools` / `skills` overlays are ignored — the runner manages its own iteration and tool exposure. The runner is expected to write its transcript into `ctx.cognitive_history` directly so the framework's history surface remains consistent.

`CognitiveWorker` does **not** itself satisfy `WorkerRunner` — the two paths are kept distinct so the dispatcher's `isinstance` check is unambiguous.

## Phase Annotation (snapshot)

`self.snapshot(...)` is an async context manager that creates scoped context overrides:

```python
async with self.snapshot(goal="Sub-task A"):
    # Original fields saved, overrides applied.
    # LayeredExposure._revealed cleared.
    yield ThinkCall("worker")  # LLM sees goal = "Sub-task A"
# Original fields + revealed state restored.
```

- Provides sub-goal scoping for focused thinking.
- Exception-safe via async context manager.
- Used internally by `AgentCall` to scope the sub-agent's context.

## Workflow Fallback Mechanism

Two distinct failure sources are handled in AMPHIFLOW mode:

**ActionCall tool failure** (a yielded tool raises during execution):

1. Step fails → `_dispatch_call` increments `state.consecutive_failures`.
2. Within `state.max_consecutive_fallbacks`: `_dispatch_call` constructs a scoped `snapshot(goal=fallback_goal)` and runs the fallback worker for `WORKFLOW_STEP_FALLBACK_MAX_ATTEMPTS`; the generator resumes via `asend()` afterward.
3. Threshold exceeded: raise `_FullFallback`, which `_dispatch_flow` catches → invoke `on_agent(ctx)` for full agent mode and return.

**Generator-internal exception** (helper / inline logic between yields raises):

- The generator is unrecoverable after a raise — `asend()` cannot resume it — so step-level fallback is impossible. `_dispatch_flow` catches the exception directly and:
  - Pure WORKFLOW mode (`can_fallback=False`): re-raises the original exception.
  - AMPHIFLOW with `on_agent` overridden: hands off to `_invoke_template(self.on_agent(ctx), …, scope="agent")`.
  - AMPHIFLOW forced via `mode=` without an `on_agent` override: raises a `RuntimeError` tagged with the failing step index.

`AgentCall` yield is orthogonal to fallback — it explicitly delegates a sub-task to agent mode (with a clean context snapshot) regardless of failure state.

## Built-in Tools Subsystem

`AmphibiousAutoma.arun()` injects a fixed roster of built-in tools into `context.tools` so every agent has a baseline capability surface — shell, filesystem, search, human input — without any per-project wiring. The roster lives in `bridgic.amphibious.builtin_tools.ALL_BUILTIN_TOOLS`; adding a new built-in only requires appending its `FunctionToolSpec` to that tuple.

### Injection resolution

```
arun(builtin_tools=...)        ← runtime kwarg (highest priority)
    └─ if None → class.builtin_tools (frozenset or None)
        └─ if None → inject every entry of ALL_BUILTIN_TOOLS
```

A non-`None` resolution must reference only valid tool names; unknown entries raise `ValueError` at `arun()` entry, surfacing typos before the LLM ever sees a missing tool. The resulting set is intersected with already-present `context.tools` by `tool_name` — user-supplied tools win, so a built-in whose name collides is silently skipped (dedup behaviour).

### Read-before-modify invariant

The filesystem-mutating built-ins (`write_file`, `edit_file`) require a prior `read_file` on the same path AND that the file has not changed externally since that read. Mechanism:

- `AmphibiousAutoma._read_tracker: Dict[str, float]` — a per-agent dict mapping absolute path → mtime at last read. Reset at every `arun()` entry, scoping the invariant to a single run.
- `read_file` records the file's mtime after a successful read (best-effort: a failed `os.stat` here is silently swallowed so it cannot mask the successful read).
- `write_file` (for existing files) and `edit_file` consult the tracker and raise `RuntimeError` if (a) the path was never read, or (b) the current mtime is newer than the recorded one.

The tools resolve the agent through the `current_agent` ContextVar, so the tracker is implicitly per-`asyncio.Task`: concurrent `arun()` calls from separate agents never share state.

### Tool exception path

Built-in tools raise on validation failures (`ValueError`, `FileNotFoundError`, `RuntimeError`, `TimeoutError`, …). They do not catch and wrap errors as `<error>...</error>` strings. The framework's per-tool exception handling — in `_action_tool_call._run_one` — captures every exception and produces:

```python
ActionStepResult(success=False, error=str(exc), tool_result=None)
```

In agent mode this becomes part of the next observation, letting the LLM see what went wrong and adapt. In workflow mode, `_run_workflow` aggregates failed `ActionStepResult`s into a `RuntimeError("Tool execution failed for: ... — ...")` and either falls back to `on_agent` (AMPHIFLOW within `max_consecutive_fallbacks`) or re-raises (pure WORKFLOW).

## Human-in-the-Loop

Three entry points all converge on `AmphibiousAutoma._dispatch_human_channel(prompt, channel=None)`:

| Entry Point | Context | Mechanism |
|-------------|---------|-----------|
| `yield HumanCall(prompt=..., channel=...)` | Any flow (`on_agent`, `on_workflow`, hooks) | `_dispatch_call` routes the yield through `_dispatch_human_channel` |
| `request_human` tool (auto-injected) | LLM-driven — any mode | Built-in tool injected into `context.tools` during `arun()`, resolved via `current_agent` ContextVar; calls `_dispatch_human_channel` |

### Channel registration via `@human_channel`

```python
@human_channel              # bare → channel name = method name
async def terminal(self, prompt: str) -> str: ...

@human_channel("feishu")    # explicit channel name
async def ask_feishu(self, prompt: str) -> str: ...
```

The `@human_channel` decorator tags a method with `_human_channel_name`. When the subclass is created, `AmphibiousAutoma.__init_subclass__` walks the MRO (via `_build_human_channel_registry`), collects every tagged method, and populates `cls._human_channels: Dict[str, str]` (channel-name → method-name). Subclass registrations win over parent declarations.

Channel handlers are **plain async methods returning `str`**, not async generators — they are leaf I/O operations.

### Channel resolution (at dispatch time)

| Registry size | `channel=None` behaviour | `channel="name"` behaviour |
|---------------|--------------------------|----------------------------|
| 0 | Falls through to `_stdin_human_fallback` (reads from stdin via `run_in_executor`) | Raises `RuntimeError("Unknown human channel: ...")` |
| 1 | Implicit default — that channel is used | Looked up in registry; raises if name not present |
| 2+ | Raises `RuntimeError("HumanCall(channel=None) is ambiguous: N channels registered…")` | Looked up in registry; raises if name not present |

The LLM-facing `request_human` tool always passes `channel=None`, so when multiple channels are registered the agent must keep at least one of them as the unambiguous default — otherwise `request_human` will raise at call time.

### Concurrency

`request_human` uses `contextvars.ContextVar` (`current_agent`) for late-binding. Each `asyncio.Task` (each `arun()`) gets its own isolated binding — concurrent agents sharing the same tool object never interfere.
