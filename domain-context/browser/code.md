# Browser Domain — Phase 5 Code Generation Context

## Domain reference files to read

- `{PLUGIN_ROOT}/skills/bridgic-browser/references/sdk-guide.md` and `{PLUGIN_ROOT}/skills/bridgic-browser/references/cli-sdk-api-mapping.md` — SDK tool names and usage.

## Faithful to exploration report

`on_workflow` in `agents.py` must implement **every numbered step (and sub-step)** from the report's "Operation Sequence" — same order, same refs, same values.

## Action principle — never modify page state via JavaScript

**Do not use `evaluate_javascript_on_ref` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements.** JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `evaluate_javascript_on_ref` is only acceptable for **reading** data from the page, never for writing.

**Use the appropriate browser tools (`input_text_by_ref`, `click_element_by_ref`, etc.) for all interactions that modify page state.** These tools trigger the correct events and ensure the page's internal state stays consistent with the visible UI.

## Action conventions

- `ActionCall` tool names must match SDK method names (not CLI command names). See `cli-sdk-api-mapping.md`.
- **Explicit `wait_for` after every browser action.** Every browser operation (`navigate_to`, `click_element_by_ref`, `input_text_by_ref`, etc.) must be immediately followed by a `yield ActionCall("wait_for", ...)` call. Recommended durations by action type:

  | Action type | Wait (seconds) |
  |---|---|
  | Navigation / full page load | 3–5 |
  | Click that triggers content loading (search, filter, tab switch) | 3–5 |
  | Click that opens dropdown / toggles UI element | 1–2 |
  | Text input / form fill | 1–2 |
  | Close tab / minor UI action | 1–2 |

  Adjust based on actual observed response times during exploration.

## Observation management

**Do NOT call `get_snapshot_text` inside `on_workflow` to read page state.** The `observation()` hook keeps `ctx.observation` up-to-date — read it directly. The only exception is when `on_workflow` needs a snapshot before hooks have run (e.g., the very first state check after navigation).

## `agents.py` hooks — `observation` and `after_action`

*`observation` — live browser state before each step.* Called automatically before each `yield` in `on_workflow` and each OTC cycle. Returns the current browser state (open tabs + page snapshot) for `ctx.observation`:

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

*`after_action` — mandatory override for observation refresh.* Called automatically after each tool call. Refreshes `ctx.observation` once `wait_for` completes. Critical for browser projects — without it, inline code between a `wait_for` yield and the next yield sees stale page state.

```python
async def after_action(self, step_result, ctx):
    action_result = step_result.result
    if hasattr(action_result, "results"):
        for step in action_result.results:
            if step.tool_name == "wait_for" and step.success:
                ctx.observation = await self.observation(ctx)
                break
```

## `workers.py` — add a `browser` field to `CognitiveContext`

Declare `browser` (the `Browser` SDK instance) on your `CognitiveContext` subclass and mark it `json_schema_extra={"display": False}` — it is a non-serializable resource and must not be serialized into the LLM prompt.

## `helpers.py` — extraction from `ctx.observation`

Helpers parse the accessibility tree text in `ctx.observation` and must be written based on the actual a11y tree structure observed during exploration (see the snapshot files under `{PROJECT_ROOT}/.bridgic/explore/`).

```python
def find_active_tab(observation: str) -> Optional[str]:
    """Find the active tab's page_id."""
    if not observation:
        return None
    match = re.search(r'(page_\d+)\s*\(active\)', observation)
    return match.group(1) if match else None
```

## `main.py` — browser lifecycle, run mode, LLM init, tool assembly, and runtime goal

- **Run mode**: set `mode=RunMode.AMPHIFLOW` if project mode is *Amphiflow*, otherwise `mode=RunMode.WORKFLOW`.
- **LLM initialization** (based on the **LLM configured** flag from Phase 2, not the project mode):
  - **LLM configured = yes**: initialize `OpenAILlm` from `.env` / environment variables and pass `llm=llm` to the agent constructor.
  - **LLM configured = no**: pass `llm=None` to the agent constructor. Do not import or initialize any LLM classes.
- **Browser lifecycle**: `async with Browser(...) as browser` — create in `main.py`, store in context.
  - **Isolated mode**: set `user_data_dir` to `{PROJECT_ROOT}/.bridgic/browser/` so the generated project runs in its own clean browser profile.
  - **Default mode**: omit `user_data_dir` (use the browser's default profile).
  - All other launch parameters (headless, channel, args, viewport, etc.) must mirror those recorded in the exploration report from Phase 4 — otherwise, under Default mode the shared browser state observed during exploration may not be reachable at runtime.
- **Browser tools**: `BrowserToolSetBuilder.for_tool_names(browser, ...)` selecting only the SDK methods used in the exploration.
- **Goal at runtime**: read the project's `task.md` file and pass its full content as the `goal` parameter to `agent.arun()`.

```python
import asyncio
from pathlib import Path
from bridgic.amphibious import RunMode
from bridgic.browser.session import Browser
from bridgic.browser.tools import BrowserToolSetBuilder
from tools import ALL_TASK_TOOLS
# When LLM configured = yes, also:
# from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration
# from config import LLM_API_BASE, LLM_API_KEY, LLM_MODEL

async def main():
    # LLM configured = yes:
    #   llm = OpenAILlm(
    #       api_key=LLM_API_KEY,
    #       api_base=LLM_API_BASE,
    #       configuration=OpenAIConfiguration(model=LLM_MODEL, temperature=0.0, max_tokens=16384),
    #       timeout=180.0,
    #   )
    # LLM configured = no:
    llm = None

    # Project mode = Amphiflow:
    #   mode = RunMode.AMPHIFLOW
    # Project mode = Workflow:
    mode = RunMode.WORKFLOW

    # Launch parameters below must mirror the exploration report's recorded values.
    # Under Isolated mode also pass user_data_dir="<PROJECT_ROOT>/.bridgic/browser/".
    async with Browser(headless=False) as browser:
        builder = BrowserToolSetBuilder.for_tool_names(
            browser,
            "navigate_to",
            # ...others based on exploration
            strict=True,
        )
        browser_tools = builder.build()["tool_specs"]
        all_tools = [*browser_tools, *ALL_TASK_TOOLS]

        goal = Path("task.md").read_text()

        agent = MyAgent(llm=llm, verbose=True)
        await agent.arun(
            goal=goal,
            browser=browser,
            tools=all_tools,
            mode=mode,
        )

if __name__ == "__main__":
    asyncio.run(main())
```

## `task.md`

Copy the user's `{PROJECT_ROOT}/TASK.md` content verbatim into the generated project's `task.md` file.
