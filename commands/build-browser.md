---
description: >-
  End-to-end pipeline that turns a browser automation task into a working
  bridgic-amphibious project. TRIGGER when the user says like: "provides a browser
  task and wants to generate an amphibious project from it"; or "generate a project
  from this browser workflow". The pipeline covers: task
  initialization → pipeline configuration → environment setup → CLI
  exploration → SDK code generation → verification.
---

# Build Browser Pipeline

Turn a browser task into a working bridgic-amphibious project.

## Pipeline Workflow

```
1. Initialize Task          (this command — generate TASK.md template, user fills in task details)
2. Configure Pipeline       (this command — project mode, LLM config if needed, browser mode)
3. Setup Environment        (this command, runs setup-env.sh)
4. CLI Exploration          (→ amphibious-explore agent)
5. Generate Amphibious Code (→ amphibious-code agent)
6. Verify                   (→ amphibious-verify agent)
```

> **Path variables**: `{PLUGIN_ROOT}` and `{PROJECT_ROOT}` are path placeholders — all paths below use these prefixes. If either is missing, the plugin was not loaded correctly — do not proceed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their browser automation task. Write the following template: `{PLUGIN_ROOT}/templates/build-task-template.md`. The template includes instructions and sections for the user to fill in. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill it in.

Wait for the user to confirm they have filled in the template. Then read `{PROJECT_ROOT}/TASK.md` and extract the *Task Description*:
- Goal
- Expected Output
- Other optional details (starting URL, notes, constraints, special instructions, etc.)

If any required section (Goal, Expected Output) is empty, ask the user to complete it before proceeding.

---

## Phase 2: Configure Pipeline

Present the following configuration questions **in order** as numbered choices. The user selects by entering the number (e.g., `1` or `2`). Wait for each answer before proceeding. All interactions with user to confirm use `AskUserQuestion` tool to present the question and capture the answer.

### 2a. Project Mode

Present the options as:

> Choose project mode:
>
> **1. Workflow** — Every step runs deterministically. Best for stable, predictable tasks.
>
> **2. Amphiflow** — Every step runs normally, but switches to AI when something unexpected happens (CAPTCHA, layout change, etc.). Requires LLM config.
>

Record the chosen **project mode** — it affects code generation in Phase 5.

#### LLM configuration

**If the user chose Amphiflow**, immediately validate LLM configuration:

```bash
bash "{PLUGIN_ROOT}/scripts/run/check-dotenv.sh"
```

- **Exit 0**: LLM variables present — proceed.
- **Exit 1**: missing variables listed in output. Create `.env` file and ask the user to set them in it, then re-run the script. Do not proceed until it exits 0.

**If the user chose Workflow**, analyze the task description from TASK.md to determine whether LLM is still needed:

1. **Task clearly requires LLM** — The task description contains explicit AI/model demands such as: intelligent summarization, AI-based classification, natural language generation, semantic analysis, content understanding that cannot be achieved with deterministic rules, or the user explicitly mentions using AI/LLM/model. In this case, inform the user that their task involves AI-powered operations and LLM configuration is needed, then run the same `.env` validation check above. Do not ask — proceed directly.

2. **Task is ambiguous** — The task description contains operations that *could* involve AI but are not explicitly stated (e.g., "extract key information", "analyze content", "generate a report"). Present the question:

   > Your task description mentions operations that may benefit from AI/LLM capabilities (e.g., content analysis, intelligent extraction). Would you like to configure an LLM?
   >
   > **1. Yes** — Configure LLM for AI-powered processing.
   >
   > **2. No** — Run purely with deterministic scripts, no AI.
   >
   > Enter **1** or **2**:

   If the user chose **1**, run the `.env` validation check above. If **2**, skip.

3. **Task clearly does not require LLM** — The task is purely mechanical (page navigation, clicking, form-filling, data scraping with fixed selectors, file download). Skip LLM configuration entirely.

### 2b. Browser Environment Mode

Present the options as:

> Choose browser environment:
>
> **1. Default** — Shared browser state across phases (login sessions carry over).
>
> **2. Isolated** — Each phase gets a clean browser profile, auto-cleaned after use. Ensures reproducible runs.
>
> Enter **1** or **2** (default: 1):

Record the chosen **browser mode** — it affects Phases 4, 5, and 6.

Confirm understanding with the user (task summary from TASK.md + project mode + browser mode) before proceeding.

---

## Phase 3: Setup Environment

Initialize an **empty uv project** in the working directory.

```bash
bash "{PLUGIN_ROOT}/scripts/run/setup-env.sh"
```

Checks that `uv` is on PATH and runs `uv init` if `pyproject.toml` is absent.

- **Exit 0**: Capture the `ENV_READY` block from stdout as the environment details passed to later phases.
- **Exit non-zero**: `uv` is not installed or init failed. Surface the error to the user and **stop the entire pipeline**.

Do not proceed until the script exits 0.

---

## Phase 4: CLI Exploration

**Delegate to the `amphibious-explore` agent.**

Pass to the agent:

- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - Output directory `{PROJECT_ROOT}/.bridgic/explore/`
  - The agent must record the full browser launch parameters used in this phase (headless, channel, args, etc., excluding `user-data-dir`) into the exploration report.
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`. The agent must create this directory before launching the browser, and **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** after exploration is complete and resources are cleaned up, so that subsequent phases start with a clean browser state.
- **Domain context** (browser automation, pre-distilled — copy verbatim into §1):

  **Domain reference files to read**:
  - `{PLUGIN_ROOT}/skills/bridgic-browser/references/cli-guide.md` for CLI tool names and usage
  - `{PLUGIN_ROOT}/skills/bridgic-browser/references/env-vars.md` for environment variables that affect browser behavior (e.g., headless mode, channel selection, stealth mode, etc.)

  **Observation protocol** — run both commands together before every action to capture the current environment state:

  ```bash
  uv run bridgic-browser snapshot       # current tab's page state
  uv run bridgic-browser tabs           # all open tabs + which is active
  ```

  - Use `tabs` to track open tabs and identify the active tab so subsequent actions target the correct page context.
  - `snapshot` has two output modes (the CLI decides automatically):
    - **Minimal content** — the full snapshot is printed to stdout; locate target elements directly in the terminal output.
    - **Substantial content** — only a file path is printed; search for task-related keywords in that file, or read it in full to find the target elements and their refs.

  **Cleanup protocol** — run once at the end of exploration to release all browser processes started by `bridgic-browser`:

  ```bash
  uv run bridgic-browser close
  ```

**Do not proceed to Phase 5 until complete.**

---

## Phase 5: Generate Amphibious Code

**Delegate to the `amphibious-code` agent.**

Pass to the agent:
- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - **LLM configured** from Phase 2 — whether LLM environment was validated (yes/no).
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`
  - The exploration report path: `{PROJECT_ROOT}/.bridgic/explore/exploration_report.md` from Phase 4.
- **Domain context** (browser automation) — browser-specific instructions that override or supplement the `amphibious-code` agent's general per-file rules:

  **Domain reference files to read**:
  - `{PLUGIN_ROOT}/skills/bridgic-browser/references/sdk-guide.md` and `{PLUGIN_ROOT}/skills/bridgic-browser/references/cli-sdk-api-mapping.md` for SDK tool names and usage
  - `{PLUGIN_ROOT}/templates/build-browser-code-patterns.md` — browser-specific code patterns for all project files

  **Faithful to exploration report** — `on_workflow` in `agents.py` must implement every numbered step (and sub-step) from the report's "Operation Sequence" — same order, same refs, same values.

  **Action principle — never modify page state via JavaScript.** Do not use `evaluate_javascript_on_ref` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements. JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `evaluate_javascript_on_ref` is only acceptable for **reading** data from the page, never for writing.

  **Action conventions**:
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

  **Observation management — do NOT call `get_snapshot_text` inside `on_workflow` to read page state.** The `observation()` hook keeps `ctx.observation` up-to-date — read it directly. The only exception is when `on_workflow` needs a snapshot before hooks have run (e.g., the very first state check after navigation).

  **`agents.py` hooks — `observation` and `after_action`**:

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

  **`workers.py` — add a `browser` field to `CognitiveContext`.** Declare `browser` (the `Browser` SDK instance) on your `CognitiveContext` subclass and mark it `json_schema_extra={"display": False}` — it is a non-serializable resource and must not be serialized into the LLM prompt.

  **`helpers.py` — extraction from `ctx.observation`.** Helpers parse the accessibility tree text in `ctx.observation` and must be written based on the actual a11y tree structure observed during exploration (see the snapshot files under `{PROJECT_ROOT}/.bridgic/explore/`).

  ```python
  def find_active_tab(observation: str) -> Optional[str]:
      """Find the active tab's page_id."""
      if not observation:
          return None
      match = re.search(r'(page_\d+)\s*\(active\)', observation)
      return match.group(1) if match else None
  ```

  **`main.py` — browser lifecycle, run mode, LLM init, tool assembly, and runtime goal**:
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

  **`task.md`** — copy the user's `{PROJECT_ROOT}/TASK.md` content verbatim into the generated project's `task.md` file.

---

## Phase 6: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent:
- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - Exploration report and snapshot files from `{PROJECT_ROOT}/.bridgic/explore/`. Please cross-check `on_workflow` against the report's "Operation Sequence" and treat any missing step as a bug to fix.
  - Work directory of the generated project from Phase 5
  - **If Default browser mode**: verify the generated `main.py`'s browser launch parameters match those recorded in the exploration report from Phase 4. Mismatches under Default mode break shared-state assumptions and must be fixed.
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`. The agent must override `user_data_dir` in the debug-instrumented code to this path. After verification is complete and all resources are cleaned up, **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** to leave a clean state.
