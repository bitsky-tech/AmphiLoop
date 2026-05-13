# Browser Domain — Code Generation Context

Every browser action is dispatched through the `bridgic-browser` CLI, invoked via the framework's auto-injected `bash` built-in tool. `on_workflow` in `amphi.py` must implement **every numbered step (and sub-step)** from the exploration report's "Operation Sequence" — same order and execution logic.

## Domain reference files

- `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` — the command list.
- `bridgic-browser <cmd> -h` — per-command flags.

---

## Phase 2: `amphi.py` overrides

### 2.2 Context (`CognitiveContext` subclass)

The persistent browser process is owned by the CLI, so the Context does not need a `browser` field. Otherwise `amphibious-code.md` §2.2 still applies — add state-tracking fields (counters, processed-id sets, progress markers) when the task accumulates progress across yields.

```python
from pydantic import Field
from bridgic.amphibious import CognitiveContext

class AmphiContext(CognitiveContext):
    # processed_ids: set[str] = Field(default_factory=set)
    pass
```

### 2.3 Helpers — extraction from `ctx.observation`

Helpers exist **only for VOLATILE data** — values that change per page-load, per row, or per run. Base every helper on the actual a11y tree text under `{PROJECT_ROOT}/.bridgic/explore/`. Same split threshold as `amphibious-code.md` §2.3 (>5 helpers or >300 lines → `helpers.py`).

```python
import re

def extract_list_rows(observation: str) -> list[dict[str, str]]:
    """Per-row data from the filtered list. Refs and ids are VOLATILE."""
    ...
```

### 2.5 `on_workflow`

Translate the exploration report's "Operation Sequence" into yields, with browser-specific conventions below.

**Each browser action is a `bash` ActionCall on `bridgic-browser`.** The exploration step's CLI command goes through verbatim — STABLE refs interpolate as `@<hex>` arguments:

```python
yield ActionCall("bash", command=f"uv run bridgic-browser click @{SEARCH_BUTTON_REF}", description="Click Search to submit")
```

**STABLE refs as module-level constants.** For every ref tagged STABLE in the exploration report, declare a constant near the top of `amphi.py` and interpolate it inline at the yield site. VOLATILE refs are extracted per-iteration via §2.3 helpers.

```python
# Top of amphi.py — copy from exploration_report.md §2 (STABLE-tagged steps).
STATUS_DROPDOWN_REF = "5dc3463e"
SEARCH_BUTTON_REF   = "4084c4ad"
NEXT_BUTTON_REF     = "cbac3327"
```

**Explicit `wait` after every state-mutating action** — itself a `bridgic-browser` subcommand:

```python
yield ActionCall("bash", command="uv run bridgic-browser wait 3", description="Wait for results to load")
```

Recommended durations:

| Action type | seconds |
|---|---|
| Navigation / full page load | 3–5 |
| Click that triggers content loading | 3–5 |
| Click that opens dropdown / toggles UI | 1–2 |
| Text input / form fill | 1–2 |
| Close tab / minor UI action | 1–2 |

Condition-based waits use a text argument: `bridgic-browser wait "Submit"` waits until "Submit" appears, `bridgic-browser wait --gone "Loading"` waits until "Loading" disappears.

**Never modify page state via JavaScript.** Don't use `eval-on` (or any JS execution) to set form values, trigger clicks, or manipulate DOM. JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `eval-on` is acceptable for **reading** data only, never for writing.

**No `bridgic-browser snapshot` / `tabs` from inside `on_workflow`** — state reads belong in the §2.7 hook layer (`observation` or `after_action`); `on_workflow` reads `ctx.observation` directly.

### 2.7 Hooks — `observation` and `after_action`

**Mandate**: write an `observation` hook in every browser project that outputs the **same 3-section format** the explore wrapper (`browser-observe.sh`) produces — `=== ACTION ===` / `=== POST-ACTION TABS ===` / `=== POST-ACTION SNAPSHOT ===`. Saved artifacts (`.bridgic/explore/*.txt`) use the same format. VOLATILE resolvers (`H.find_X(observation)`) anchor on the section headers and work identically against both.

**Plus a guarded `after_action` for post-wait refresh**: `observation` runs only *before* each yield in workflow, so helper code reading `ctx.observation` *between* yields (extracting a ref from the just-finished snapshot, deciding the next click target) would see pre-wait state. `after_action` re-fetches tabs + snapshot whenever the just-completed action was `bridgic-browser wait`, writing the same 3-section format into `ctx.observation`.

```python
from pathlib import Path
from bridgic.amphibious import (
    ActionCall, ActionResult, AmphibiousAutoma, RETURN,
)


class Amphi(AmphibiousAutoma[AmphiContext]):

    @staticmethod
    def _format_observation(tabs_result, snap_result) -> str:
        """3-section observation string with snapshot auto-resolve."""
        tabs_out = str(tabs_result[0].result) if tabs_result and tabs_result[0].result else ""
        snap_out = str(snap_result[0].result) if snap_result and snap_result[0].result else ""
        # Auto-resolve: snapshot defaults to `-l 10000`; anything larger comes
        # back as `[notice] saved to: <path>` — read the file inline.
        if snap_out.startswith("[notice] saved to:"):
            snap_out = Path(snap_out.split("[notice] saved to:", 1)[1].strip()).read_text()
        return (
            "=== ACTION ===\n\n"
            f"=== POST-ACTION TABS ===\n{tabs_out}\n\n"
            f"=== POST-ACTION SNAPSHOT ===\n{snap_out}"
        )

    async def observation(self, ctx):
        tabs = yield ActionCall("bash", command="uv run bridgic-browser tabs", description="List open tabs")
        snap = yield ActionCall("bash", command="uv run bridgic-browser snapshot", description="Snapshot current page")
        yield RETURN(self._format_observation(tabs, snap))

    async def after_action(self, step_result, ctx):
        action_result = step_result.result
        if not isinstance(action_result, ActionResult):
            return
        for step in action_result.results:
            if not (step.success and step.tool_name == "bash"):
                continue
            cmd = (step.tool_arguments or {}).get("command", "")
            if "bridgic-browser wait" not in cmd:
                continue
            tabs = yield ActionCall("bash", command="uv run bridgic-browser tabs", description="List open tabs")
            snap = yield ActionCall("bash", command="uv run bridgic-browser snapshot", description="Snapshot after wait")
            ctx.observation = self._format_observation(tabs, snap)
            return
```

**Auto-resolve contract**: wrapper output (what the explore agent ingests into LLM context) stays unresolved; saved artifacts and `ctx.observation` at runtime (refreshed by either hook) all resolve `[notice] saved to:` to the file content. See `domain-context/browser/explore.md` for the artifact-save rule.

**Why the `wait` filter**: clicks / fills don't settle the DOM immediately — the workflow follows them with a `wait`. Refreshing only after `wait` captures stable state and avoids two extra browser calls per non-settling action.

---

## Phase 3: `main.py` overrides

The `bash` built-in is auto-injected, so `tools=` only carries any custom `TASK_TOOLS`. Cleanup goes in `finally` so the persistent browser process is released on either successful exit or unexpected raise.

- **Launch parameters** (headless, viewport, channel, etc.) are **not** surfaced as flags on `bridgic-browser` action commands, so the only runtime injection point is the `BRIDGIC_BROWSER_JSON` env var on the daemon-startup process. The single source of truth is the file `{PROJECT_ROOT}/.bridgic/bridgic-browser.json` written during exploration; `main.py` just bridges that file into the env var at startup (no Browser params constructed in Python, no duplicated JSON dict).
- **Default vs Isolated** is purely a difference inside the JSON file: Isolated mode adds a `"user_data_dir": "<PROJECT_ROOT>/.bridgic/browser"` entry; Default mode omits the key (and the browser falls back to its persistent profile at `~/.bridgic/bridgic-browser/user_data/`). `main.py` does not branch on the mode — it just reads whatever the file contains.
- **Goal**: hardcode the task description as a string in `main.py`. Multi-line descriptions go into a triple-quoted constant.

Run-mode and LLM initialization follow `amphibious-code.md` §3 — no browser-specific override.

```python
import asyncio
import os
import subprocess
from pathlib import Path

from dotenv import load_dotenv
from bridgic.amphibious import RunMode

# Only when llm_configured = yes:
# from bridgic.llms.openai import OpenAILlm, OpenAIConfiguration

from amphi import Amphi, AmphiContext, TASK_TOOLS

PROJECT_ROOT = Path(__file__).parent.parent
BROWSER_CONFIG = PROJECT_ROOT / ".bridgic" / "bridgic-browser.json"

GOAL = """
<paste the task description here; multi-line OK>
""".strip()


async def main():
    # .env lives at PROJECT_ROOT (one level above this file's directory).
    load_dotenv(PROJECT_ROOT / ".env")

    # Bridge the browser config file into the env var the daemon reads at
    # startup. The file is the single source of truth (written during
    # exploration); main.py does not construct browser params here.
    if BROWSER_CONFIG.exists():
        os.environ["BRIDGIC_BROWSER_JSON"] = BROWSER_CONFIG.read_text()

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
