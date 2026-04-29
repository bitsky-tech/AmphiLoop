# Browser Domain — Code Generation Context

## Domain reference files to read

**MUST** read `{PLUGIN_ROOT}/skills/bridgic-browser/references/sdk-guide.md` and `{PLUGIN_ROOT}/skills/bridgic-browser/references/cli-sdk-api-mapping.md` — SDK tool names and usage.

## Faithful to exploration report

`on_workflow` in `amphi.py` must implement **every numbered step (and sub-step)** from the report's "Operation Sequence" — same order, same refs, same values.

## Action principle — never modify page state via JavaScript

**Do not use `evaluate_javascript_on_ref` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements.** JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `evaluate_javascript_on_ref` is only acceptable for **reading** data from the page, never for writing.

## Action conventions

- `ActionCall` tool names must match SDK method names (not CLI command names). See `cli-sdk-api-mapping.md`.
- **Explicit `wait_for` after every browser action.** Every state-mutating call is followed by `yield ActionCall("wait_for", time_seconds=<n>, description="...")`. Condition-based waits use `text=` / `text_gone=` / `selector=` (see `cli-sdk-api-mapping.md`). Recommended durations:

  | Action type | `time_seconds` |
  |---|---|
  | Navigation / full page load | 3–5 |
  | Click that triggers content loading | 3–5 |
  | Click that opens dropdown / toggles UI | 1–2 |
  | Text input / form fill | 1–2 |
  | Close tab / minor UI action | 1–2 |

  Adjust to actual observed response times.

## Observation management

**Do NOT call `get_snapshot_text` inside `on_workflow` to read page state.** The `observation()` hook keeps `ctx.observation` up-to-date — read it directly. The only exception is when `on_workflow` needs a snapshot before hooks have run (e.g., the very first state check after navigation).

---

## `amphi.py` — browser-specific implementation

### Context (`CognitiveContext` subclass)

Add a `browser` field — the SDK `Browser` instance — and mark it `json_schema_extra={"display": False}`. It is a non-serializable resource and must not be serialized into the LLM prompt.

```python
from typing import Any
from pydantic import Field
from bridgic.amphibious import CognitiveContext

class AmphiContext(CognitiveContext):
    browser: Any = Field(default=None, json_schema_extra={"display": False})
```

### Hooks — `observation` and `after_action`

**`observation` — live browser state before each step.** Called automatically before each `yield` in `on_workflow` and each OTC cycle. Returns the current browser state (open tabs + page snapshot) for `ctx.observation`:

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

**`after_action` — mandatory override for observation refresh.** Called automatically after each tool call. Refreshes `ctx.observation` once `wait_for` completes. Critical for browser projects — without it, inline code between a `wait_for` yield and the next yield sees stale page state.

```python
async def after_action(self, step_result, ctx):
    action_result = step_result.result
    if hasattr(action_result, "results"):
        for step in action_result.results:
            if step.tool_name == "wait_for" and step.success:
                ctx.observation = await self.observation(ctx)
                break
```

### Ref handling — STABLE vs VOLATILE

Browser refs are **deterministic per element**: the same DOM element on the same page yields the same ref string across observations and across runs (until that page navigates or its DOM is mutated). This is what makes `STABLE` annotations in the exploration report meaningful — those refs were captured once during exploration and remain valid at runtime.

**Mirror that distinction directly in `amphi.py`:**

- **STABLE refs → module-level constants.** For every ref tagged STABLE in the exploration report (header buttons, fixed dropdowns, pagination Next, search controls, etc.), declare a constant near the top of `amphi.py` and reference it inline at the yield site. **No `find_<name>_ref(observation)` parser** — the value is already known and re-deriving it by regex is pure waste.

  ```python
  # Top of amphi.py — copy these from exploration_report.md §2 (STABLE-tagged steps).
  STATUS_DROPDOWN_REF = "5dc3463e"
  SEARCH_BUTTON_REF   = "4084c4ad"
  NEXT_BUTTON_REF     = "cbac3327"

  # In on_workflow:
  yield ActionCall("click_element_by_ref",
                   description="Open the status filter dropdown",
                   ref=STATUS_DROPDOWN_REF)
  ```

- **VOLATILE refs → extracted per-iteration.** Per-row buttons, dynamically generated list items, and any element whose ref regenerates on each page load go in `ctx.observation` and must be parsed at runtime — see Helpers below.

If the exploration report doesn't list a ref for an element your `on_workflow` needs, that's an exploration gap — go look in `{PROJECT_ROOT}/.bridgic/explore/` artifacts and copy the literal hex ref out of the snapshot. Do not add a regex parser to "auto-discover" it.

### Helpers — extraction from `ctx.observation`

Helpers exist **only for VOLATILE data** — values that change per page-load, per row, or per run. Parsers for STABLE elements do not belong here (see "Ref handling" above). Base every helper on the actual a11y tree text under `{PROJECT_ROOT}/.bridgic/explore/`.

```python
import re
from typing import Optional

def find_active_tab(observation: str) -> Optional[str]:
    """Active tab's page_id. VOLATILE — regenerated per browser session."""
    if not observation:
        return None
    match = re.search(r'(page_\d+)\s*\(active\)', observation)
    return match.group(1) if match else None

def extract_list_rows(observation: str) -> list[dict[str, str]]:
    """Per-row data from the filtered list. Refs and ids are VOLATILE."""
    ...
```

Keep helpers as module-level functions in `amphi.py` (split into a sibling `helpers.py` only if extraction logic grows large). When several VOLATILE values come out of the same observation block, return them together from one helper — don't write a separate finder per field.

---

## `main.py` — browser lifecycle, run mode, LLM init, tool assembly

- **Browser lifecycle**: `async with Browser(...) as browser` — create in `main.py`, store in context.
  - **Isolated mode**: set `user_data_dir` to `{PROJECT_ROOT}/.bridgic/browser/` (resolved at runtime as `Path(__file__).parent.parent / ".bridgic" / "browser"`). Matches the path used by Phase 3 exploration and Phase 5 verification, so the same isolated profile chain carries through every phase.
  - **Default mode**: omit `user_data_dir` (use the browser's default profile).
  - All other launch parameters (headless, channel, args, viewport, etc.) must mirror those recorded in the exploration report — otherwise, under Default mode the shared browser state observed during exploration may not be reachable at runtime.
- **Browser tools**: `BrowserToolSetBuilder.for_tool_names(browser, ...)` selecting only the SDK methods used in the exploration.
- **Goal**: hardcode the task description as a string in `main.py`. Multi-line descriptions go into a triple-quoted constant. Do not read it from a sibling file — the project should be runnable as-is from its own directory.

Run-mode (`RunMode.WORKFLOW` / `RunMode.AMPHIFLOW`) and LLM initialization (`llm=llm` vs `llm=None`) follow the generic rules in `amphibious-code.md` — no browser-specific override.

```python
import asyncio
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from bridgic.amphibious import RunMode
from bridgic.browser.session import Browser
from bridgic.browser.tools import BrowserToolSetBuilder

# Only when llm_configured = yes:
# from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration

from amphi import Amphi, AmphiContext, TASK_TOOLS

LOG_DIR = Path(__file__).parent / "log"

GOAL = """
<paste the task description here; multi-line OK>
""".strip()


async def main():
    # .env lives at PROJECT_ROOT (one level above this file's directory).
    load_dotenv(Path(__file__).parent.parent / ".env")

    LOG_DIR.mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        handlers=[
            logging.FileHandler(LOG_DIR / "run.log"),
            logging.StreamHandler(),
        ],
    )

    # llm_configured = no:
    llm = None
    # llm_configured = yes:
    # llm = OpenAILlm(
    #     api_key=os.getenv("LLM_API_KEY"),
    #     api_base=os.getenv("LLM_API_BASE"),
    #     configuration=OpenAIConfiguration(
    #         model=os.getenv("LLM_MODEL"),
    #         temperature=0.0,
    #         max_tokens=16384,
    #     ),
    #     timeout=180.0,
    # )

    # Launch parameters below mirror the exploration report's recorded values.
    # Under Isolated mode also pass
    # user_data_dir=Path(__file__).parent.parent / ".bridgic" / "browser"
    # (i.e. {PROJECT_ROOT}/.bridgic/browser/).
    async with Browser(headless=False) as browser:
        builder = BrowserToolSetBuilder.for_tool_names(
            browser,
            "navigate_to",
            # ...others based on exploration's Operation Sequence
            strict=True,
        )
        browser_tools = builder.build()["tool_specs"]
        all_tools = [*browser_tools, *TASK_TOOLS]

        agent = Amphi(llm=llm, verbose=True)
        # context carries `browser` (non-serializable) and `goal`; `tools` MUST
        # go to arun() — context.tools is `CognitiveTools`, not a list.
        await agent.arun(
            context=AmphiContext(browser=browser, goal=GOAL),
            tools=all_tools,
            mode=RunMode.WORKFLOW,  # or RunMode.AMPHIFLOW
        )


if __name__ == "__main__":
    asyncio.run(main())
```
