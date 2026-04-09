# Code Patterns for Browser-to-Amphibious

## Table of Contents

- [Browser tools via BrowserToolSetBuilder](#browser-tools-via-browsertoolsetbuilder)
- [Task-specific tools](#task-specific-tools)
- [Hooks: observation, after_action, before_action](#hooks-observation-after_action-before_action)
- [Helpers: extracting data from ctx.observation](#helpers-extracting-data-from-ctxobservation)
- [on_workflow patterns](#on_workflow-patterns)
- [on_agent pattern](#on_agent-pattern)
- [config: Project config](#config-project-config)
- [main: Browser lifecycle and tool assembly](#main-browser-lifecycle-and-tool-assembly)

---

## Browser Tools via BrowserToolSetBuilder

The bridgic-browser SDK provides `BrowserToolSetBuilder` to create `FunctionToolSpec` objects directly compatible with bridgic-amphibious. Tool names match SDK method names.

### Select by tool names (preferred)

Pick only the SDK methods that correspond to CLI commands used during exploration:

```python
from bridgic.browser.tools import BrowserToolSetBuilder

builder = BrowserToolSetBuilder.for_tool_names(
    browser,
    "navigate_to",
    "get_snapshot_text",
    "click_element_by_ref",
    "input_text_by_ref",
    "select_dropdown_option_by_ref",
    "wait_for",
    strict=True,
)
browser_tools = builder.build()["tool_specs"]
```

### Select by category

```python
from bridgic.browser.tools import BrowserToolSetBuilder, ToolCategory

builder = BrowserToolSetBuilder.for_categories(
    browser,
    ToolCategory.NAVIGATION,
    ToolCategory.ELEMENT_INTERACTION,
)
browser_tools = builder.build()["tool_specs"]
```

---

## Task-Specific Tools

For operations beyond browser interaction (saving data, computing results, human intervention), write standard async tools registered via `FunctionToolSpec.from_raw()`:

```python
from bridgic.core.agentic.tool_specs import FunctionToolSpec

async def save_record(item_id: str, title: str, detail: str) -> str:
    """Save an extracted record.

    Parameters
    ----------
    item_id : str
        Unique identifier.
    title : str
        Item title.
    detail : str
        Extracted content.
    """
    # Replace with actual persistence
    ...
```

---

## Hooks: observation, after_action, before_action

### observation — live browser state before each step

Called automatically **before** each `yield` in `on_workflow` and each OTC cycle. Returns the current information for `ctx.observation`. Including tabs and snapshot.

```python
async def observation(self, ctx) -> Optional[str]:
    if ctx.browser is None:
        return "No browser available."
    
    parts = []
    tabs = await ctx.browser.get_tabs()
    if tabs:
        parts.append(f"[Open tabs]\n{tabs}")
    snapshot = await ctx.browser.get_snapshot_text(limit=1000000)
    if snapshot:
        parts.append(f"[Snapshot]\n{snapshot}")
    return "\n\n".join(parts) if parts else "No page loaded."
```

### before_action — track state and sanitize

Use for state tracking and argument sanitization. Receives `List[Tuple[ToolCall, ToolSpec]]`:

```python
async def before_action(self, decision_result, ctx):
    for tool_call, _ in decision_result:
        name = tool_call.name
        args = tool_call.arguments

        ...  # Some logic

    return decision_result
```

### after_action — mandatory override for observation refresh

Called automatically after each tool call. Refresh to get the newest page state after `wait_for` completes. This is critical for browser projects — without it, the agent sees stale page state between a `wait_for` yield and the next yield.

```python
async def after_action(self, step_result, ctx):
    action_result = step_result.result
    if hasattr(action_result, "results"):
        for step in action_result.results:
            if step.tool_name == "wait_for" and step.success:
                ctx.observation = await self.observation(ctx)
                break
```

Additional optional uses (add alongside the mandatory refresh as needed):
- **Result accumulation**: aggregate tool call results
- **Logging / notifications**: log step outcomes for debugging
- **Conditional recovery**: detect failure patterns in `step_result` and set flags for `on_workflow`

---

## Helpers: Extracting Data from ctx.observation

Helpers are **only needed for dynamic extraction** — NOT for deterministic steps. They parse the accessibility tree text in `ctx.observation` and must be written based on the actual a11y tree structure observed.

### Common pattern: extract tab info

```python
def find_active_tab(observation: str) -> Optional[str]:
    """Find the active tab's page_id."""
    if not observation:
        return None
    match = re.search(r'(page_\d+)\s*\(active\)', observation)
    return match.group(1) if match else None


def extract_ref(observation: str) -> Optional[str]:
    ...
```

---

## on_workflow Patterns

### Deterministic steps

For deterministic steps where the target elements are stable (e.g., navigation buttons, filters, search controls), use the ref values directly from CLI exploration:

```python
async def on_workflow(self, ctx):
    # Every browser action is followed by wait_for with a duration tuned to the action type
    yield ActionCall("navigate_to", description="Open target page", url=ctx.target_url)
    yield ActionCall("wait_for", description="Wait for page to load", time_seconds=4)

    yield ActionCall("click_element_by_ref", description="Click status dropdown", ref="063b563b")
    yield ActionCall("wait_for", description="Wait for dropdown to open", time_seconds=1)

    yield ActionCall("click_element_by_ref", description="Select 'Pending' option", ref="05d0a863")
    yield ActionCall("wait_for", description="Wait for selection to apply", time_seconds=1)

    yield ActionCall("click_element_by_ref", description="Click search button", ref="4084c4ad")
    yield ActionCall("wait_for", description="Wait for results to load", time_seconds=3)
```

### Dynamic steps

For dynamic steps where the target elements are volatile (list items, search results, paginated rows), extract identifiers from `ctx.observation` at runtime using helpers:

```python
async def on_workflow(self, ctx):
    # ... deterministic steps above ...

    # Dynamic: process each item from the current page
    items = extract_items(ctx.observation)  # helper from helpers.py
    for item in items:
        yield ActionCall("navigate_to", description=f"Open detail: {item['title']}", url=item["url"])
        yield ActionCall("wait_for", description="Wait for detail page", time_seconds=3)

        # ctx.observation is refreshed by the observation() hook before each yield
        detail = extract_detail(ctx.observation)  # helper from helpers.py
        yield ActionCall("save_record", description="Save extracted data", **detail)

        yield ActionCall("go_back", description="Return to list page")
        yield ActionCall("wait_for", description="Wait for list reload", time_seconds=2)
```

Key differences from deterministic steps:
- Refs and identifiers come from `ctx.observation`, not hardcoded
- Extraction functions in `helpers.py` parse the live accessibility tree
- `observation()` hook keeps `ctx.observation` fresh before each `yield`

---

## on_agent Pattern

Full LLM-driven. The LLM sees `ctx.observation` (live page state) and decides what tool to call each round:

```python
from bridgic.amphibious import (
    AmphibiousAutoma, CognitiveWorker, think_unit, ErrorStrategy,
)

class MyAgent(AmphibiousAutoma[MyContext]):
    main_think = think_unit(
        CognitiveWorker.inline(
            "You are a browser automation executor. Executing exactly one action per round.\n\n"
            "# Critical Rules\n"
            "1. **ONE ACTION AT A TIME**: Your step_content and tool call MUST describe the same "
            "single action.\n"
            "2. **COMPLETION**: Set finish=True ONLY when ALL steps of the current phase are fully "
            "accomplished and verified.\n\n"
            "**Respond with a JSON object.**"
        ),
        max_attempts=50,
        on_error=ErrorStrategy.RAISE,
    )

    async def on_agent(self, ctx):
        await self.main_think
```

---

## config: Project config

The LLM config or other variables

```python
import os

from dotenv import load_dotenv

load_dotenv()

LLM_API_BASE = os.getenv("LLM_API_BASE")
LLM_API_KEY = os.getenv("LLM_API_KEY")
LLM_MODEL = os.getenv("LLM_MODEL")

```

---

## main: Browser Lifecycle and Tool Assembly

The `Browser` instance is created in main.py, stored in context, and passed to `BrowserToolSetBuilder`:

```python
import asyncio
from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration
from bridgic.browser.session import Browser
from bridgic.browser.tools import BrowserToolSetBuilder

from config import LLM_API_KEY, LLM_API_BASE, LLM_MODEL

async def main():
    llm = OpenAILlm(
        api_key=LLM_API_KEY,
        api_base=LLM_API_BASE,
        configuration=OpenAIConfiguration(
            model=LLM_MODEL,
            temperature=0.0,
            max_tokens=16384,
        ),
        timeout=180
    )

    async with Browser(headless=False) as browser:
        # Browser tools from SDK
        builder = BrowserToolSetBuilder.for_tool_names(
            browser,
            "navigate_to", "get_snapshot_text", "click_element_by_ref",
            "input_text_by_ref", "switch_tab", "close_tab", "wait_for",
            strict=True,
        )
        browser_tools = builder.build()["tool_specs"]
        all_tools = [*browser_tools, *get_task_tools()]

        goal = "..."  # From task.md

        agent = MyAgent(llm=llm, verbose=True)
        await agent.arun(
            goal=goal,
            browser=browser,
            tools=all_tools
        )

if __name__ == "__main__":
    asyncio.run(main())
```