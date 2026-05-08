# Bridgic Amphibious Code Patterns

## Table of Contents
- [Minimal Agent (Agent Mode)](#minimal-agent-agent-mode)
- [Workflow Mode](#workflow-mode)
- [Direct LLM Call (LLMCall)](#direct-llm-call-llmcall)
- [Returning Values (RETURN)](#returning-values-return)
- [Built-in Tools](#built-in-tools)
- [Human-in-the-Loop](#human-in-the-loop)
- [Amphiflow Mode](#amphiflow-mode)
- [Sub-Agent Delegation (AgentCall)](#sub-agent-delegation-agentcall)
- [WorkerRunner — External Runtime](#workerrunner--external-runtime)
- [Custom CognitiveWorker](#custom-cognitiveworker)
- [Structured Output (output_schema)](#structured-output-output_schema)
- [Custom Context](#custom-context)
- [Phase Annotation](#phase-annotation)
- [Cognitive Policies](#cognitive-policies)
- [OTC Hooks (yield form)](#otc-hooks-yield-form)
- [Skills Usage](#skills-usage)
- [Memory Configuration](#memory-configuration)
- [Conditional Loops](#conditional-loops)
- [Tool & Skill Filtering](#tool--skill-filtering)
- [Execution Tracing](#execution-tracing)

---

## Minimal Agent (Agent Mode)

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, CognitiveWorker, think_unit,
    ThinkCall,
)
from bridgic.core.agentic.tool_specs import FunctionToolSpec

# 1. Define tools
async def get_weather(city: str) -> str:
    """Get current weather for a city."""
    return f"Sunny, 22°C in {city}"

get_weather_tool = FunctionToolSpec.from_raw(get_weather)

# 2. Define agent — on_agent is an async generator that yields ThinkCall.
class WeatherAgent(AmphibiousAutoma[CognitiveContext]):
    planner = think_unit(
        CognitiveWorker.inline("Look up weather and provide a summary."),
        max_attempts=5,
    )

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("planner")

# 3. Run
agent = WeatherAgent(llm=llm, verbose=True)
result = await agent.arun(
    goal="Check the weather in Tokyo and London.",
    tools=[get_weather_tool],
)
print(agent.final_answer)  # auto-captured from finishing think step
```

## Workflow Mode

Pure workflow mode runs deterministically and does not need an LLM — only override `on_workflow`, leave `on_agent` alone.

```python
from bridgic.amphibious import ActionCall, RETURN

class WeatherWorkflow(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx: CognitiveContext):
        tokyo = yield ActionCall("get_weather", city="Tokyo")
        london = yield ActionCall("get_weather", city="London")

        tokyo_val = tokyo[0].result if tokyo else "N/A"
        london_val = london[0].result if london else "N/A"
        yield RETURN(f"Tokyo: {tokyo_val}, London: {london_val}")

workflow = WeatherWorkflow()  # No LLM needed for pure workflow mode
result = await workflow.arun(
    goal="Check weather",
    tools=[get_weather_tool],
)
print(workflow.final_answer)
```

## Direct LLM Call (LLMCall)

`LLMCall` is a yield primitive that invokes `self._llm` via a bridgic-core protocol — useful for one-shot LLM operations that don't warrant a full think_unit. Three protocols, three return types.

```python
from bridgic.amphibious import ActionCall, LLMCall, RETURN
from bridgic.core.model.protocols import PydanticModel
from pydantic import BaseModel

class Summary(BaseModel):
    headline: str
    bullets: list[str]

class Reporter(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx):
        # 1. Plain chat — returns str
        title = yield LLMCall.chat("Generate a one-line title for a quarterly report.")

        # 2. Structured output — returns typed instance
        files = yield ActionCall("glob", pattern="**/*.md", path="/abs/repo")
        summary = yield LLMCall.structure_output(
            f"Summarize this list of files:\n{files[0].result}",
            constraint=PydanticModel(model=Summary),
        )

        # 3. Tool selector — returns (List[ToolCall], Optional[str])
        # (rarely yielded directly; structure_output / chat cover most cases)

        yield RETURN(f"{title}\n{summary.headline}")
```

## Returning Values (RETURN)

PEP 525 forbids `return value` inside async generators. Use `yield RETURN(value)` whenever you want to communicate a return value out of the generator:

| Where | Effect of `yield RETURN(value)` |
|-------|--------------------------------|
| `on_agent` / `on_workflow` | `value` becomes `agent.final_answer` (overrides the auto-capture from history) |
| `observation` hook | `value` becomes `ctx.observation` (string) |
| `before_action` hook | `value` overrides the decision (e.g. filtered tool list) |
| `after_action` hook | Ignored — the framework does not consume `after_action`'s return value |

```python
async def on_agent(self, ctx):
    yield ThinkCall("plan")
    yield ThinkCall("execute")
    yield RETURN("All tasks complete.")   # explicit final answer
```

Anything yielded after a `RETURN` is unreachable — the dispatcher captures the value, closes the generator, and returns.

## Built-in Tools

Every `AmphibiousAutoma` agent receives seven built-in tools in `context.tools` automatically — no manual wiring. Names are snake_case and work in every mode.

| Tool | Purpose |
|------|---------|
| `request_human` | Ask the human operator a question (HITL) |
| `bash` | Execute a shell command |
| `read_file` | Read a file with line numbers (required before `write_file` / `edit_file`) |
| `write_file` | Create or overwrite a file |
| `edit_file` | Exact-string replacement with uniqueness check |
| `glob` | Find files by pattern |
| `grep` | Regex search across files |

### Default — relying on auto-injection

```python
from bridgic.amphibious import ThinkCall

class CodeAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(
        CognitiveWorker.inline("Investigate the codebase and report findings."),
        max_attempts=20,
    )

    async def on_agent(self, ctx):
        yield ThinkCall("worker")

# All seven built-ins are present. Anything you pass in tools=[...] is added
# on top, deduped by name.
await CodeAgent(llm=llm).arun(goal="What does this repo do?")
```

### Calling built-ins from on_workflow

```python
from bridgic.amphibious import ActionCall

class ConfigPatcher(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx):
        files = yield ActionCall("glob", pattern="**/conf.yaml", path="/abs/repo")
        # Read-before-edit invariant: each path must be read first.
        yield ActionCall("read_file", file_path="/abs/repo/conf.yaml")
        yield ActionCall(
            "edit_file",
            file_path="/abs/repo/conf.yaml",
            old_string="threshold: 5",
            new_string="threshold: 10",
        )
```

### Restricting which built-ins are injected

```python
from bridgic.amphibious import ThinkCall

class ReadOnlyAgent(AmphibiousAutoma[CognitiveContext]):
    # Class-level filter — these and only these are injected by arun().
    builtin_tools = frozenset({"request_human", "read_file", "glob", "grep"})

    worker = think_unit(CognitiveWorker.inline("Audit the code."), max_attempts=10)

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
```

```python
# Runtime override — wins over the class attribute.
await agent.arun(goal="quick read-only sweep", builtin_tools=["read_file", "grep"])

# Empty iterable opts out entirely.
await agent.arun(goal="...", builtin_tools=[])
```

Unknown names fail loudly at `arun()` entry — `frozenset({"read_files"})` (typo) raises `ValueError` rather than silently producing a tool-less agent.

### Combining with think_unit tool filters

`think_unit(tools=[...])` filters by tool name. Built-in names work the same as any user tool, which lets you gate phases by capability:

```python
from bridgic.amphibious import ThinkCall

class PhaseGated(AmphibiousAutoma[CognitiveContext]):
    investigate = think_unit(
        CognitiveWorker.inline("Investigate."),
        tools=["read_file", "glob", "grep"],   # exploration only
        max_attempts=10,
    )
    apply = think_unit(
        CognitiveWorker.inline("Apply the planned change."),
        tools=["read_file", "edit_file"],       # no bash, no overwrite
        max_attempts=5,
    )

    async def on_agent(self, ctx):
        yield ThinkCall("investigate")
        yield ThinkCall("apply")
```

### Read-before-modify safety in practice

`write_file` (for existing files) and `edit_file` refuse to act on a path that hasn't been read in the current `arun()` call, AND refuse if the file's mtime advanced between read and modify. The tracker is reset at every `arun()` entry, so the invariant is per-run.

```python
async def on_workflow(self, ctx):
    # Without this read, the next ActionCall raises RuntimeError.
    yield ActionCall("read_file", file_path="/abs/conf.yaml")
    yield ActionCall(
        "edit_file",
        file_path="/abs/conf.yaml",
        old_string="threshold: 5",
        new_string="threshold: 10",
    )
```

## Human-in-the-Loop

Three entry points share one event channel — the `@human_channel` registry. They all route through `agent._dispatch_human_channel(prompt, channel=None)`.

### Entry 1: HumanCall in any flow

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, CognitiveWorker, think_unit,
    ActionCall, HumanCall, ThinkCall, RETURN,
)

class ConfirmableWorkflow(AmphibiousAutoma[CognitiveContext]):
    async def on_workflow(self, ctx: CognitiveContext):
        result = yield ActionCall(
            "search_flights",
            origin="Beijing", destination="Tokyo", date="2024-06-01",
        )
        feedback = yield HumanCall(prompt="Found flights. Book CA123?")
        if feedback == "yes":
            yield ActionCall("book_flight", flight_number="CA123")
        else:
            yield RETURN("Booking cancelled by user.")
```

```python
class InteractiveAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(CognitiveWorker.inline("Execute step."), max_attempts=10)

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("worker")
        feedback = yield HumanCall(prompt="Task complete. Any follow-up?")
        if feedback != "no":
            async with self.snapshot(goal=feedback):
                yield ThinkCall("worker")
```

### Entry 2: LLM tool (autonomous)

`request_human` is auto-injected as one of the [built-in tools](#built-in-tools), so the LLM can call it in any mode — agent, workflow fallback, or amphiflow — without manual wiring:

```python
class AutonomousAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(
        CognitiveWorker.inline(
            "Execute the task. Ask request_human when you need user input."
        ),
        max_attempts=10,
    )

    async def on_agent(self, ctx):
        yield ThinkCall("worker")

agent = AutonomousAgent(llm=llm)
await agent.arun(goal="Plan a trip", tools=[search_tool])
```

### Entry 3: Custom channel via `@human_channel`

Replace the built-in stdin handler with your UI integration:

```python
from bridgic.amphibious import human_channel

class WebAgent(AmphibiousAutoma[CognitiveContext]):
    @human_channel  # bare form → channel name = "websocket"
    async def websocket(self, prompt: str) -> str:
        return await ws_client.send_and_receive(prompt)

    worker = think_unit(CognitiveWorker.inline("Plan the task."), max_attempts=5)

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
        feedback = yield HumanCall(prompt="Confirm?")  # routes to .websocket()
```

Multi-channel example with explicit selection:

```python
class MultiChannelAgent(AmphibiousAutoma[CognitiveContext]):
    @human_channel("feishu")
    async def ask_feishu(self, prompt: str) -> str:
        return await feishu_client.send_and_wait(prompt)

    @human_channel("email")
    async def ask_email(self, prompt: str) -> str:
        return await email_client.send_and_wait(prompt)

    async def on_workflow(self, ctx):
        yield ActionCall("do_something", arg="value")
        # With 2+ channels registered, channel=None is ambiguous — must specify.
        feedback = yield HumanCall(prompt="Confirm?", channel="feishu")
```

## Amphiflow Mode

When a class overrides both `on_agent` and `on_workflow`, `RunMode.AUTO`
resolves to `AMPHIFLOW`: the workflow runs deterministically, and on a step
failure the agent is invoked to recover. You may also pass
`mode=RunMode.AMPHIFLOW` explicitly.

```python
from bridgic.amphibious import RunMode, ActionCall, ThinkCall

class FormFiller(AmphibiousAutoma[CognitiveContext]):
    fixer = think_unit(
        CognitiveWorker.inline("Diagnose the problem and fix it."),
        max_attempts=5,
    )

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("fixer")

    async def on_workflow(self, ctx: CognitiveContext):
        yield ActionCall("fill_field", field_name="username", value="john")
        yield ActionCall("fill_field", field_name="email", value="john@example.com")
        yield ActionCall("click_button", button_name="submit")

# Workflow runs; on failure, agent takes over automatically
agent = FormFiller(llm=llm, verbose=True)
result = await agent.arun(
    goal="Fill and submit the form",
    tools=[fill_field_tool, click_button_tool, solve_captcha_tool],
    mode=RunMode.AMPHIFLOW,
    max_consecutive_fallbacks=2,
)
```

## Sub-Agent Delegation (AgentCall)

`AgentCall` is **only valid in `on_workflow`**. It snapshots the context (fresh `goal`, optional `history` / `tools` / `skills` filters) and recursively re-enters `on_agent` to handle the sub-task. It scopes *what the sub-agent sees* — not *how it thinks*.

```python
from bridgic.amphibious import ActionCall, AgentCall, ThinkCall

class PriceAdvisor(AmphibiousAutoma[CognitiveContext]):
    advisor = think_unit(
        CognitiveWorker.inline("Analyze prices and propose next steps."),
        max_attempts=5,
    )

    async def on_agent(self, ctx):
        yield ThinkCall("advisor")

    async def on_workflow(self, ctx):
        yield ActionCall("search_price", platform="Amazon", product="laptop")
        yield ActionCall("search_price", platform="eBay", product="laptop")

        # Delegate complex analysis to LLM (clean context snapshot).
        # tools / skills are filtered by name — sub-agent only sees these.
        yield AgentCall(
            goal="Analyze prices and decide if we need more platforms.",
            tools=["search_price", "request_human"],
            skills=["price_analysis"],
        )
```

For a single named cognitive step inside `on_agent`, declare a `think_unit` and `yield ThinkCall("name")` — `AgentCall` is the deterministic→autonomous transition, not a generic "run a worker" primitive.

## WorkerRunner — External Runtime

For external agent runtimes (Claude Code, OpenAI Agents, bespoke ReAct stacks) that have their own internal loop, implement the `WorkerRunner` Protocol. The dispatcher detects the protocol and skips the OTC cycle — calling `run(agent, ctx)` directly.

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveContext, WorkerRunner,
    ThinkCall, think_unit,
)

class ClaudeCodeRunner:
    """Plug-in WorkerRunner — manages its own loop, tools, history."""

    async def run(self, agent: AmphibiousAutoma, ctx: CognitiveContext) -> None:
        # Subprocess out to claude, feed it ctx.goal, write the resulting
        # transcript into ctx.cognitive_history so the framework's history
        # surface stays consistent.
        transcript = await self._invoke_claude(ctx.goal)
        for entry in transcript:
            ctx.add_info(Step(content=entry.content, result=entry.tool_result))

class HybridAgent(AmphibiousAutoma[CognitiveContext]):
    # WorkerRunner detected automatically; until / max_attempts / tools / skills
    # overlays are ignored — the runner owns its own iteration.
    external = think_unit(ClaudeCodeRunner())
    polish = think_unit(CognitiveWorker.inline("Polish the answer."), max_attempts=3)

    async def on_agent(self, ctx):
        yield ThinkCall("external")
        yield ThinkCall("polish")
```

## Custom CognitiveWorker

```python
from bridgic.amphibious import CognitiveWorker, CognitiveContext, ThinkCall

class DestinationAnalyzer(CognitiveWorker):
    async def thinking(self) -> str:
        return "Analyze the destination and suggest a day-by-day plan."

    async def observation(self, context: CognitiveContext):
        return (
            f"Current goal: {context.goal}\n"
            f"Tip: Visit attractions early morning to avoid crowds."
        )

class TravelPlanner(AmphibiousAutoma[CognitiveContext]):
    analyzer = think_unit(DestinationAnalyzer(), max_attempts=3)
    planner = think_unit(
        CognitiveWorker.inline("Create a detailed itinerary."),
        max_attempts=5,
    )

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("analyzer")
        yield ThinkCall("planner")
```

## Structured Output (output_schema)

```python
from pydantic import BaseModel, Field
from bridgic.amphibious import ThinkCall

class PlanResult(BaseModel):
    phases: list[str] = Field(description="Execution phases")
    estimated_steps: int = Field(description="Total steps needed")

class PlannerAgent(AmphibiousAutoma[CognitiveContext]):
    planner = think_unit(
        CognitiveWorker.inline(
            "Create a step-by-step execution plan.",
            output_schema=PlanResult,
        ),
        max_attempts=1,
    )

    async def on_agent(self, ctx: CognitiveContext):
        plan = yield ThinkCall("planner")  # PlanResult instance via asend()
        print(plan.phases)
```

## Custom Context

```python
from pydantic import Field, ConfigDict
from bridgic.amphibious import (
    CognitiveContext, ActionResult, ThinkCall,
)

class DocumentContext(CognitiveContext):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    current_document: str = Field(
        default="",
        description="Name of the document being analyzed",
    )
    analysis_results: dict = Field(
        default_factory=dict,
        description="Accumulated results keyed by document name",
    )
    internal_state: str = Field(
        default="",
        json_schema_extra={"display": False},  # Hidden from LLM
    )

class DocumentAnalyzer(AmphibiousAutoma[DocumentContext]):
    analyzer = think_unit(
        CognitiveWorker.inline("Analyze the current document."),
        max_attempts=5,
    )

    # Plain coroutine — _invoke_template accepts coroutines as well as
    # async generators. Use a coroutine when the hook has no yields.
    async def after_action(self, step_result, ctx: DocumentContext):
        """Keep custom context in sync with tool results."""
        action_result = step_result.result
        if isinstance(action_result, ActionResult):
            for step in action_result.results:
                if step.success and step.tool_name == "read_document":
                    doc_name = step.tool_arguments.get("doc_name", "")
                    ctx.current_document = doc_name
                    ctx.analysis_results[doc_name] = step.tool_result

    async def on_agent(self, ctx: DocumentContext):
        yield ThinkCall("analyzer")
```

## Phase Annotation

```python
from bridgic.amphibious import ThinkCall

class ContentCreator(AmphibiousAutoma[CognitiveContext]):
    researcher = think_unit(
        CognitiveWorker.inline("Research the topic thoroughly."),
        max_attempts=3,
    )
    writer = think_unit(
        CognitiveWorker.inline("Write the article using gathered research."),
        max_attempts=5,
    )

    async def on_agent(self, ctx: CognitiveContext):
        # Phase 1: Research
        async with self.snapshot(goal="Gather research material on renewable energy"):
            yield ThinkCall("researcher")

        # Phase 2: Write
        async with self.snapshot(goal="Write the article using the research"):
            yield ThinkCall("writer")
```

## Cognitive Policies

```python
from bridgic.amphibious import ThinkCall

class AnalystAgent(AmphibiousAutoma[CognitiveContext]):
    analyst = think_unit(
        CognitiveWorker.inline(
            "Perform a comprehensive analysis.",
            enable_rehearsal=True,    # Mental simulation
            enable_reflection=True,   # Information assessment
            # Acquiring is always active by default
        ),
        max_attempts=10,
    )

    async def on_agent(self, ctx: CognitiveContext):
        yield ThinkCall("analyst")
```

## OTC Hooks (yield form)

Hooks are async generators with **hook scope** — `ActionCall`, `HumanCall`, `LLMCall`, `RETURN` are allowed; `AgentCall` and `ThinkCall` are not. `RETURN(value)` overrides the hook's effective return; exhausting without `RETURN` is treated as passthrough.

### observation — Inject Custom Perception

```python
from bridgic.amphibious import ActionCall, RETURN

class BrowserAgent(AmphibiousAutoma[CognitiveContext]):
    worker = think_unit(CognitiveWorker.inline("Operate the browser."), max_attempts=5)

    async def observation(self, ctx: CognitiveContext):
        # Run a tool inside the hook to derive the observation.
        snapshot = yield ActionCall("bridgic-browser", action="snapshot")
        yield RETURN(f"Page snapshot:\n{snapshot[0].result}")

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
```

A worker can also have its own `observation()` method that delegates to the agent-level hook by returning `_DELEGATE`:

```python
from bridgic.amphibious import _DELEGATE

class SecurityWorker(CognitiveWorker):
    async def thinking(self) -> str:
        return "Analyze the system for security issues."

    async def observation(self, context: CognitiveContext):
        return _DELEGATE  # falls through to agent-level observation
```

### build_messages — Reshape LLM Messages (worker-level)

```python
from bridgic.core.model.types import Message

class StrictWorker(CognitiveWorker):
    async def thinking(self) -> str:
        return "Perform a security audit."

    async def build_messages(self, think_prompt, tools_description,
                             output_instructions, context_info):
        rules = "\n\nRULES:\n1. NEVER call delete_file.\n2. NEVER read .env files."
        system = f"{think_prompt}{rules}\n\n{tools_description}\n\n{output_instructions}"
        return [
            Message.from_text(text=system, role="system"),
            Message.from_text(text=context_info, role="user"),
        ]
```

### before_action — Filter Dangerous Calls

```python
from bridgic.amphibious import RETURN

class SafeAgent(AmphibiousAutoma[CognitiveContext]):
    auditor = think_unit(CognitiveWorker.inline("Audit the system."), max_attempts=5)

    async def before_action(self, decision_result, ctx):
        if isinstance(decision_result, list):
            blocked = {"delete_file", "drop_table"}
            filtered = [(tc, ts) for tc, ts in decision_result
                        if ts.tool_name not in blocked]
            yield RETURN(filtered or decision_result)

    async def on_agent(self, ctx):
        yield ThinkCall("auditor")
```

### after_action — Update Context After Execution

```python
from bridgic.amphibious import ActionResult, ThinkCall

class TrackingAgent(AmphibiousAutoma[MyContext]):
    worker = think_unit(CognitiveWorker.inline("Process data."), max_attempts=5)

    # Plain coroutine form — no yields, no need for the generator stub.
    async def after_action(self, step_result, ctx: MyContext):
        action_result = step_result.result
        if isinstance(action_result, ActionResult):
            for r in action_result.results:
                if r.success:
                    ctx.processed_count += 1

    async def on_agent(self, ctx):
        yield ThinkCall("worker")
```

### action_custom_output — Post-process Structured Output

```python
from pydantic import BaseModel
from bridgic.amphibious import ThinkCall

class AuditReport(BaseModel):
    findings: list[str]
    risk_level: str

class RedactingAgent(AmphibiousAutoma[CognitiveContext]):
    auditor = think_unit(
        CognitiveWorker.inline("Produce an audit report.", output_schema=AuditReport),
        max_attempts=1,
    )

    # action_custom_output is a plain coroutine, not a generator.
    async def action_custom_output(self, decision_result, ctx):
        if isinstance(decision_result, AuditReport):
            decision_result.findings = [
                f.replace("sk-xxx", "[REDACTED]") for f in decision_result.findings
            ]
        return decision_result

    async def on_agent(self, ctx):
        yield ThinkCall("auditor")
```

## Skills Usage

```python
from bridgic.amphibious import Skill

fundamental_skill = Skill(
    name="fundamental-analysis",
    description="Evaluate stock's intrinsic value using financial metrics",
    content="## Procedure\n1. Get financials\n2. Evaluate P/E ratio\n...",
)

agent = MyAgent(llm=llm)
result = await agent.arun(
    goal="Analyze AAPL stock",
    tools=[get_financials_tool],
    skills=[fundamental_skill],
)

# Or load from file
ctx = CognitiveContext(goal="...")
ctx.skills.add_from_file("skills/analysis/SKILL.md")
ctx.skills.load_from_directory("skills/")
```

## Memory Configuration

```python
from bridgic.amphibious import CognitiveHistory

# Short tasks: large working memory
history = CognitiveHistory(working_memory_size=10, short_term_size=30)

# Long tasks: aggressive compression
history = CognitiveHistory(
    working_memory_size=2,
    short_term_size=5,
    compress_threshold=3,
)

agent = MyAgent(llm=llm)
result = await agent.arun(
    goal="Long running task",
    tools=[...],
    cognitive_history=history,
)
```

## Conditional Loops

`ThinkCall` accepts the same overlay parameters as `think_unit(...)`. Pass `until=...` (with optional `max_attempts` / `tools` / `skills`) to loop:

```python
from bridgic.amphibious import ThinkCall

class IterativeAgent(AmphibiousAutoma[CognitiveContext]):
    researcher = think_unit(
        CognitiveWorker.inline("Research ONE aspect of the topic."),
        max_attempts=10,
    )

    async def on_agent(self, ctx: CognitiveContext):
        # Loop until condition met
        yield ThinkCall(
            "researcher",
            until=lambda ctx: len(ctx.cognitive_history) >= 3,
        )

        # Loop with dynamic override
        yield ThinkCall(
            "researcher",
            until=lambda ctx: some_condition(ctx),
            max_attempts=50,
            tools=["search"],
        )
```

## Tool & Skill Filtering

```python
from bridgic.amphibious import ThinkCall

class MultiPhaseAgent(AmphibiousAutoma[CognitiveContext]):
    searcher = think_unit(
        CognitiveWorker.inline("Search for information."),
        max_attempts=5,
        tools=["search", "browse"],       # Only these tools visible
        skills=["research"],              # Only these skills visible
    )
    writer = think_unit(
        CognitiveWorker.inline("Write the report."),
        max_attempts=3,
        tools=["write_file"],
    )

    async def on_agent(self, ctx):
        yield ThinkCall("searcher")
        yield ThinkCall("writer")
```

## Execution Tracing

```python
agent = MyAgent(llm=llm, verbose=True)
result = await agent.arun(
    goal="...",
    tools=[...],
    trace_running=True,
)

# Access trace
trace = agent._agent_trace.build()
# trace["phases"]: steps grouped by self.snapshot() blocks
# trace["orphan_steps"]: steps outside any phase annotation

for step in trace["orphan_steps"]:
    content = step.step_content if hasattr(step, "step_content") else step.get("step_content", "")
    print(f"  {content[:80]}")
    tool_calls = step.tool_calls if hasattr(step, "tool_calls") else step.get("tool_calls", [])
    for tc in tool_calls:
        name = tc.tool_name if hasattr(tc, "tool_name") else tc.get("tool_name", "?")
        print(f"    -> {name}")

# Save / Load
agent._agent_trace.save("trace.json")
loaded = AgentTrace.load("trace.json")  # Returns plain dict
```
