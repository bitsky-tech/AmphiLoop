# Browser Domain — Code Generation Context

## Default route — CLI through the `bash` built-in

`bridgic-browser` ships both a CLI and a Python SDK. Codegen should **default to the CLI driven through the framework's `bash` built-in tool**: every exploration step is already a `bridgic-browser <subcommand>` invocation, and `bash` lets `on_workflow` re-issue those commands verbatim — no SDK tool wiring, no `BrowserToolSetBuilder`. Escalate to the Python SDK only when the task genuinely needs Python-side control (parallel browser sessions, async coordination beyond a one-shot command, or a capability `bridgic-browser --help` does not expose). Escalate the **whole project** at once — do not mix `bash` CLI calls with a Python-launched `Browser(...)` in the same run, the two would be separate processes with diverging state.

## Domain reference files to read

- **CLI default:** `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` for the command list; `bridgic-browser <cmd> --help` for per-command flags.
- **SDK escalation:** `{PLUGIN_ROOT}/skills/bridgic-browser/references/sdk-guide.md`, with `cli-sdk-api-mapping.md` as the CLI-name → SDK-method lookup when porting exploration steps.

## Faithful to exploration report

`on_workflow` in `amphi.py` must implement **every numbered step (and sub-step)** from the report's "Operation Sequence" — same order, same refs, same values.

## Action principle — never modify page state via JavaScript

**Do not use `evaluate_javascript_on_ref` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements.** JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `evaluate_javascript_on_ref` is only acceptable for **reading** data from the page, never for writing.

## Action conventions

- **Each browser action is a `bash` ActionCall on `bridgic-browser`.** The exploration step's CLI command goes through verbatim — refs and runtime values become flag values:

  ```python
  yield ActionCall("bash",
                   description="Click Search",
                   command=f"uv run bridgic-browser click_element_by_ref --ref {SEARCH_BUTTON_REF}")
  ```

- **Explicit `wait_for` after every state-mutating action** — itself a `bridgic-browser` subcommand:

  ```python
  yield ActionCall("bash",
                   description="Wait for results to load",
                   command="uv run bridgic-browser wait_for --time-seconds 3")
  ```

  Condition-based waits go through `--text` / `--text-gone` / `--selector` (see `bridgic-browser wait_for --help`). Recommended durations:

  | Action type | `time_seconds` |
  |---|---|
  | Navigation / full page load | 3–5 |
  | Click that triggers content loading | 3–5 |
  | Click that opens dropdown / toggles UI | 1–2 |
  | Text input / form fill | 1–2 |
  | Close tab / minor UI action | 1–2 |

  Adjust to actual observed response times.

- **Cleanup belongs in `main.py`'s `finally`,** not in `on_workflow`. One `uv run bridgic-browser close` after `arun()` returns or raises releases the persistent browser process even on partial failure.

## Observation management

The `observation()` hook keeps `ctx.observation` fresh for `on_workflow` and any agent-mode fallback. **Do not call `bridgic-browser snapshot` (or `tabs`) from inside `on_workflow`** — read `ctx.observation` directly. The only exception is when `on_workflow` needs a snapshot before any hook has run (e.g., the very first state check after navigation).

---

## `amphi.py` — browser-specific implementation

### Context (`CognitiveContext` subclass)

CLI route — no extra fields by default; the persistent browser process is owned by the CLI, not by Python:

```python
from bridgic.amphibious import CognitiveContext

class AmphiContext(CognitiveContext):
    pass
```

(SDK escalation: add `browser: Any = Field(default=None, json_schema_extra={"display": False})` to hold the `Browser` instance — `display=False` keeps the non-serializable resource out of the LLM prompt.)

### Hooks — `observation` and `after_action`

**`observation` — live browser state before each step.** Called automatically before each `yield` in `on_workflow` and each OTC cycle. CLI route — fetch tabs + snapshot via `asyncio.create_subprocess_exec`:

```python
import asyncio
from typing import Optional

async def observation(self, ctx) -> Optional[str]:
    async def cli(*args: str) -> str:
        proc = await asyncio.create_subprocess_exec(
            "uv", "run", "bridgic-browser", *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        out, _ = await proc.communicate()
        return out.decode().strip()

    parts = []
    tabs = await cli("tabs")
    if tabs:
        parts.append(f"[Open tabs]\n{tabs}")
    snapshot = await cli("snapshot")
    if snapshot:
        parts.append(f"[Snapshot]\n{snapshot}")
    return "\n\n".join(parts) if parts else "No page loaded."
```

(SDK escalation: replace the two `await cli(...)` calls with `await ctx.browser.get_tabs()` and `await ctx.browser.get_snapshot_text(limit=1000000)`.)

**`after_action` — mandatory override for observation refresh.** Called after each tool call. Refreshes `ctx.observation` once `wait_for` completes; without it, inline code between a `wait_for` yield and the next yield sees stale page state. CLI route detects `wait_for` by looking at the `bash` step's command:

```python
async def after_action(self, step_result, ctx):
    action_result = step_result.result
    if not hasattr(action_result, "results"):
        return
    for step in action_result.results:
        if not step.success:
            continue
        if step.tool_name == "bash" and "wait_for" in (getattr(step, "args", None) or {}).get("command", ""):
            ctx.observation = await self.observation(ctx)
            break
```

(SDK escalation: match on `step.tool_name == "wait_for"` directly, no command inspection needed.)

### Ref handling — STABLE vs VOLATILE

Browser refs are **deterministic per element**: the same DOM element on the same page yields the same ref string across observations and across runs (until that page navigates or its DOM is mutated). This is what makes `STABLE` annotations in the exploration report meaningful — those refs were captured once during exploration and remain valid at runtime.

**Mirror that distinction directly in `amphi.py`:**

- **STABLE refs → module-level constants.** For every ref tagged STABLE in the exploration report (header buttons, fixed dropdowns, pagination Next, search controls, etc.), declare a constant near the top of `amphi.py` and interpolate it inline at the yield site. **No `find_<name>_ref(observation)` parser** — the value is already known and re-deriving it by regex is pure waste.

  ```python
  # Top of amphi.py — copy these from exploration_report.md §2 (STABLE-tagged steps).
  STATUS_DROPDOWN_REF = "5dc3463e"
  SEARCH_BUTTON_REF   = "4084c4ad"
  NEXT_BUTTON_REF     = "cbac3327"

  # In on_workflow:
  yield ActionCall("bash",
                   description="Open the status filter dropdown",
                   command=f"uv run bridgic-browser click_element_by_ref --ref {STATUS_DROPDOWN_REF}")
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

## `main.py` — entry point + cleanup

CLI route: no `async with Browser(...)`, no `BrowserToolSetBuilder`. The `bash` built-in is auto-injected, so `tools=` only carries any custom `TASK_TOOLS`. Cleanup goes in `finally` so the persistent browser process is released on either successful exit or unexpected raise.

- **Launch parameters** (headless, channel, viewport, etc.) recorded in the exploration report attach to the **first** `bridgic-browser` action that boots the browser — propagate them as flags on that command (`--headless`, `--channel`, …; consult `bridgic-browser <cmd> --help`). Mismatches under Default mode break shared-state assumptions, just as they do for the SDK route.
- **Isolated mode** (browser env mode = Isolated): pass `--user-data-dir` resolved as `Path(__file__).parent.parent / ".bridgic" / "browser"` on the first `bridgic-browser` action that boots the browser. **Default mode**: omit `--user-data-dir`.
- **Goal**: hardcode the task description as a string in `main.py`. Multi-line descriptions go into a triple-quoted constant. Do not read it from a sibling file — the project should be runnable as-is from its own directory.

Run-mode (`RunMode.WORKFLOW` / `RunMode.AMPHIFLOW`) and LLM initialization (`llm=llm` vs `llm=None`) follow the generic rules in `amphibious-code.md` — no browser-specific override.

```python
import asyncio
import logging
import os
import subprocess
from pathlib import Path

from dotenv import load_dotenv
from bridgic.amphibious import RunMode

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

    agent = Amphi(llm=llm, verbose=True)
    try:
        await agent.arun(
            context=AmphiContext(goal=GOAL),
            tools=TASK_TOOLS,
            mode=RunMode.WORKFLOW,  # or RunMode.AMPHIFLOW
        )
    finally:
        # Release the persistent CLI browser process started during the run.
        subprocess.run(["uv", "run", "bridgic-browser", "close"], check=False)


if __name__ == "__main__":
    asyncio.run(main())
```

For the SDK escalation, replace the `try / finally` block with `async with Browser(...) as browser:` (mirroring the launch parameters from the exploration report; under Isolated mode also pass `user_data_dir = Path(__file__).parent.parent / ".bridgic" / "browser"`), build browser tools via `BrowserToolSetBuilder.for_tool_names(browser, ...).build()["tool_specs"]`, hold the instance on `ctx.browser`, and pass `tools=[*browser_tools, *TASK_TOOLS]` to `arun()`.
