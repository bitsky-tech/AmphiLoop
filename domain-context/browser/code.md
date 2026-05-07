# Browser Domain — Code Generation Context

Every browser action is dispatched through the `bridgic-browser` CLI, invoked via the framework's auto-injected `bash` built-in tool.

## Domain reference files to read

- `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` — the command list.
- `bridgic-browser <cmd> -h` — per-command flags.

## Faithful to exploration report

`on_workflow` in `amphi.py` must implement **every numbered step (and sub-step)** from the report's "Operation Sequence" — same order and execution logic.

## Action principle — never modify page state via JavaScript

**Do not use `eval-on` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements.** JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `eval-on` is only acceptable for **reading** data from the page, never for writing.

## Action conventions

- **Each browser action is a `bash` ActionCall on `bridgic-browser`.** The exploration step's CLI command goes through verbatim — STABLE refs interpolate as `@<hex>` arguments:

  ```python
  yield ActionCall("bash",
                   description="Click Search",
                   command=f"uv run bridgic-browser click @{SEARCH_BUTTON_REF}")
  ```

- **Explicit `wait` after every state-mutating action** — itself a `bridgic-browser` subcommand:

  ```python
  yield ActionCall("bash",
                   description="Wait for results to load",
                   command="uv run bridgic-browser wait 3")
  ```

  Recommended durations:

  | Action type | seconds |
  |---|---|
  | Navigation / full page load | 3–5 |
  | Click that triggers content loading | 3–5 |
  | Click that opens dropdown / toggles UI | 1–2 |
  | Text input / form fill | 1–2 |
  | Close tab / minor UI action | 1–2 |

  Adjust to actual observed response times.

  Condition-based waits use a text argument instead of a number: `bridgic-browser wait "Submit"` waits until "Submit" appears, `bridgic-browser wait --gone "Loading"` waits until "Loading" disappears (see `bridgic-browser wait -h`).

- **Cleanup belongs in `main.py`'s `finally`,** not in `on_workflow`. One `uv run bridgic-browser close` after `arun()` returns or raises releases the persistent browser process even on partial failure.

## Observation management

The `observation()` hook keeps `ctx.observation` fresh, automatically firing **before each OTC cycle and before each `yield` in `on_workflow`** so both the agent and the workflow see live state. **Do not call `bridgic-browser snapshot` (or `tabs`) from inside `on_workflow`** — read `ctx.observation` directly.

---

## `amphi.py` — browser-specific implementation

### Context (`CognitiveContext` subclass)

The persistent browser process is owned by the CLI, so the context does not need a `browser` field. Otherwise `amphibious-code.md` §2.2 still applies — add state-tracking fields (counters, processed-id sets, progress markers) when the task accumulates progress across yields, and leave the scaffolded base form as-is when it does not.

```python
from pydantic import Field
from bridgic.amphibious import CognitiveContext

class AmphiContext(CognitiveContext):
    # Add state-tracking fields here when the task needs them, e.g.:
    # processed_ids: set[str] = Field(default_factory=set)
    pass
```

### Ref handling — STABLE vs VOLATILE

Browser refs are **deterministic per element**: the same DOM element on the same page yields the same ref string across observations and across runs (until that page navigates or its DOM is mutated). Those refs are captured once during exploration and remain valid at runtime.

**Mirror the distinction directly in `amphi.py`:**

- **STABLE refs → module-level constants.** For every ref tagged STABLE in the exploration report (header buttons, fixed dropdowns, pagination Next, search controls, etc.), declare a constant near the top of `amphi.py` and interpolate it inline at the yield site.

  ```python
  # Top of amphi.py — copy these from exploration_report.md §2 (STABLE-tagged steps).
  STATUS_DROPDOWN_REF = "5dc3463e"
  SEARCH_BUTTON_REF   = "4084c4ad"
  NEXT_BUTTON_REF     = "cbac3327"

  # In on_workflow:
  yield ActionCall("bash",
                   description="Open the status filter dropdown",
                   command=f"uv run bridgic-browser click @{STATUS_DROPDOWN_REF}")
  ```

- **VOLATILE refs → extracted per-iteration.** Per-row buttons, dynamically generated list items, and any element whose ref regenerates on each page load go in `ctx.observation` and must be parsed at runtime — see §Helpers.

### Helpers — extraction from `ctx.observation`

Helpers exist **only for VOLATILE data** — values that change per page-load, per row, or per run. Base every helper on the actual a11y tree text under `{PROJECT_ROOT}/.bridgic/explore/`.

```python
import re

def extract_list_rows(observation: str) -> list[dict[str, str]]:
    """Per-row data from the filtered list. Refs and ids are VOLATILE."""
    ...
```

Keep helpers as module-level functions in `amphi.py`. Split into a sibling `helpers.py` only once you have **>5 helpers or >300 lines of extraction code** (the same threshold §2.3 of `amphibious-code.md` uses), or when a helper genuinely needs to be imported from more than one module. When several VOLATILE values come out of the same observation block, return them together from one helper — don't write a separate finder per field.

### Hooks — `observation` and `after_action`

**`observation` — live browser state before each step.** Fetch tabs + snapshot via `asyncio.create_subprocess_exec`:

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

**`after_action` — mandatory override for observation refresh.** Refreshes `ctx.observation` once a `wait` step completes; without it, inline code between a `wait` yield and the next yield sees stale page state. Detect `wait` by inspecting the `bash` step's command string:

```python
async def after_action(self, step_result, ctx):
    action_result = step_result.result
    if not hasattr(action_result, "results"):
        return
    for step in action_result.results:
        if not step.success:
            continue
        cmd = (getattr(step, "args", None) or {}).get("command", "")
        if step.tool_name == "bash" and "bridgic-browser wait" in cmd:
            ctx.observation = await self.observation(ctx)
            break
```

---

## `main.py` — entry point + cleanup

The `bash` built-in is auto-injected, so `tools=` only carries any custom `TASK_TOOLS`. Cleanup goes in `finally` so the persistent browser process is released on either successful exit or unexpected raise.

- **Launch parameters** (headless, viewport, channel, etc.) are **not** settable as flags on `bridgic-browser` action commands. The CLI's only launch flags are `--headed` and `--clear-user-data` on `open` / `search`. Mirror the values recorded in the exploration report through the `BRIDGIC_BROWSER_JSON` env var (or a `./bridgic-browser.json` file) — the example below uses the env var so the configuration travels with `main.py`.
- **Isolated mode** (browser env mode = Isolated): set `"user_data_dir": "<PROJECT_ROOT>/.bridgic/browser"` in the JSON config. **Default mode**: omit `user_data_dir` so the browser uses its default profile under `~/.bridgic/bridgic-browser/user_data/`. Under Default mode, mismatches with the exploration report's launch parameters break shared-state assumptions.
- **Goal**: hardcode the task description as a string in `main.py`. Multi-line descriptions go into a triple-quoted constant. Do not read it from a sibling file — the project should be runnable as-is from its own directory.

Run-mode (`RunMode.WORKFLOW` / `RunMode.AMPHIFLOW`) and LLM initialization (`llm=llm` vs `llm=None`) follow the generic rules in `amphibious-code.md` — no browser-specific override.

```python
import asyncio
import json
import os
import subprocess
from pathlib import Path

from dotenv import load_dotenv
from bridgic.amphibious import RunMode

# Only when llm_configured = yes:
# from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration

from amphi import Amphi, AmphiContext, TASK_TOOLS

GOAL = """
<paste the task description here; multi-line OK>
""".strip()


async def main():
    # .env lives at PROJECT_ROOT (one level above this file's directory).
    load_dotenv(Path(__file__).parent.parent / ".env")

    # Mirror the exploration report's launch parameters through the daemon
    # config env var. Add `user_data_dir` under Isolated mode; omit it under
    # Default mode.
    os.environ["BRIDGIC_BROWSER_JSON"] = json.dumps({
        "headless": False,
        # "user_data_dir": str(Path(__file__).parent.parent / ".bridgic" / "browser"),
    })

    llm = None  # configure OpenAILlm here when llm_configured = yes; full pattern in amphibious-code.md §3.

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
