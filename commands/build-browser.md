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
4. CLI Exploration          (→ browser-explorer agent)
5. Generate Amphibious Code (→ amphibious-generator agent)
6. Verify                   (→ amphibious-verify agent)
```

> **Path variables**: `{PLUGIN_ROOT}` and `{PROJECT_ROOT}` are the paths below use these prefixes. If either is missing, the plugin was not loaded correctly — do not proceed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their browser automation task. Write the following template: `{PLUGIN_ROOT}/examples/build-browser-task-template.md`. The template includes instructions and sections for the user to fill in. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill in it. 

Wait for the user to confirm they have filled in the template. Then read `{PROJECT_ROOT}/TASK.md` and extract the *Task Description*:
- Goal
- Expected Output
- Other optional details (starting URL, notes, constraints, special instructions, etc.)

If any required section (Goal, Expected Output) is empty, ask the user to complete it before proceeding.

---

## Phase 2: Configure Pipeline

Present the following configuration questions **in order** as numbered choices. The user selects by entering the number (e.g., `1` or `2`). Wait for each answer before proceeding.

### 2a. Project Mode

Present the options as:

> Choose project mode:
>
> **1. Workflow** — Pure script, no AI. Every step runs deterministically. Best for stable, predictable tasks.
>
> **2. Amphiflow** — Script + AI fallback. Runs the script normally, but switches to AI when something unexpected happens (CAPTCHA, layout change, etc.). Requires LLM config.
>
> Enter **1** or **2**:

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

**Delegate to the `browser-explorer` agent.**

Pass to the agent:
- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**: 
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - Output directory `{PROJECT_ROOT}/.bridgic/explore/`
  - Please initialize the required execution environment based on the skill.
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`. The agent must create this directory before launching the browser, and **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** after exploration is complete and resources are cleaned up, so that subsequent phases start with a clean browser state.

**Do not proceed to Phase 5 until complete.**

---

## Phase 5: Generate Amphibious Code

**Delegate to the `amphibious-generator` agent.**

Pass to the agent:
- **Task description** from Phase 1 (`TASK.md`)
- **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
- **Auxiliary context**: 
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **LLM configured** from Phase 2 — whether LLM environment was validated (yes/no). 
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`
  - Please initialize the required execution environment based on the skill.
  - The exploration report path: `{PROJECT_ROOT}/.bridgic/explore/exploration_report.md` from Phase 4
- **Domain context** (browser automation): Include the following browser-specific instructions in the delegation prompt:

### Domain Context to Pass

**Domain reference files to read**:
- `bridgic-browser` skill — `{PLUGIN_ROOT}/skills/bridgic-browser/references/sdk-guide.md` and `{PLUGIN_ROOT}/skills/bridgic-browser/references/cli-sdk-api-mapping.md` for SDK tool names and usage
- `{PLUGIN_ROOT}/examples/build-browser-code-patterns.md` — browser-specific code patterns for all project files

**Browser-specific per-file rules** (override or supplement the agent's general rules):

#### task.md

- Copy the user's `{PROJECT_ROOT}/TASK.md` content verbatim into the generated project's `task.md`.

#### agents.py

**Project mode affects code generation**

- **Workflow mode**: Generate only `on_workflow` with deterministic step-by-step actions with: `ActionCall`, `AgentCall` (with LLM configured = yes), and `HumanCall`.
- **Amphiflow mode**: Generate both `on_workflow` (primary path) and `on_agent` (final fallback handler).

**Element references**

- **Stable refs**: hardcode directly in `ActionCall` (e.g., `ref="4084c4ad"`). These are element identifiers from the exploration report that don't change between page visits.
- **Volatile refs** (list items, dynamic rows, search results): re-extract from `ctx.observation` at runtime using helpers.

**Interaction principles**

- **Simulate human interaction — NEVER use JavaScript to modify page state.** Do not use `evaluate_javascript_on_ref` (or any JS execution) to set form values, trigger clicks, or manipulate DOM elements. JS-based DOM changes bypass the frontend framework's event bindings — the page appears to change but internal state remains stale. `evaluate_javascript_on_ref` is only acceptable for **reading** data from the page, never for writing.
- **Dynamic parameters must be computed at runtime.** When the task description contains relative or context-dependent values (e.g., "past week", "today", "last 30 days"), compute them in `on_workflow` using Python's `datetime` module. Never hardcode dates, counts, or any value that depends on when the program runs.

**Tool call conventions**

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

**Observation management**

- **Max snapshot limit**: `observation()` must call `get_snapshot_text(limit=1000000)` to ensure the full snapshot is captured.
- **Do NOT call `get_snapshot_text` in `on_workflow`** to read page state. The `observation()` hook keeps `ctx.observation` up-to-date — read it directly. The only exception is when `on_workflow` needs a snapshot before hooks have run (e.g., the very first state check after navigation).
- **`after_action` hook (MUST override)**: refresh `ctx.observation` after `wait_for` completes. Without this, inline code between a `wait_for` yield and the next yield sees stale (pre-wait) page state. See `build-browser-code-patterns.md` for the mandatory code pattern and optional additional uses.

#### workers.py

- The `browser` field must be marked `json_schema_extra={"display": False}` — serializing a browser instance is meaningless.
- State-tracking fields (e.g., scraped item sets, counters) should remain visible.

#### helpers.py

- Extraction functions parse live `ctx.observation` at runtime. To **write** these helpers, read the snapshot files in `{PROJECT_ROOT}/.bridgic/explore/` (referenced in the exploration report) for the real a11y tree structure. Do not guess the format.

#### main.py

- **Run mode**: set `mode=RunMode.AMPHIFLOW` if project mode is *Amphiflow*, otherwise `mode=RunMode.WORKFLOW` if project mode is *Workflow*.
- **Browser lifecycle**: `async with Browser() as browser` — create in main.py, store in context.
  - **If Isolated mode**: set `user_data_dir` to `{PROJECT_ROOT}/.bridgic/browser/` so the generated project runs in its own clean browser profile.
  - **If Default mode**: omit `user_data_dir` (use the browser's default profile).
- **Browser tools**: `BrowserToolSetBuilder.for_tool_names(browser, ...)` selecting only the SDK methods used in the exploration.
- **Tool assembly**: `[*browser_tools, *task_tools]` → pass to `agent.arun(tools=all_tools)`.
- **LLM initialization** (based on the **LLM configured** flag from Phase 2, not the project mode):
  - **LLM configured = yes** : initialize `OpenAILlm` from `.env` / environment variables and pass `llm=llm` to the agent constructor.
  - **LLM configured = no** : pass `llm=None` to the agent constructor. Do not import or initialize any LLM classes.
- At runtime, read the project's `task.md` file and pass its full content as the `goal` parameter to `agent.arun()`. Load it from `task.md`.

The agent will:
1. Scaffold the project via `bridgic-amphibious create`
2. Load framework references from `bridgic-amphibious` skill + browser domain references from above
3. Complete all project files based on the scaffold created by `bridgic-amphibious create`

**Proceed directly to Phase 6**. Code quality issues are the sole responsibility of the amphibious-verify agent — it will run the project, detect errors from actual execution, and fix them with proper diagnosis.

---

## Phase 6: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent:
- **Task description** from Phase 1 (`TASK.md`)
- **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
- **Auxiliary context**: 
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - Please initialize the required execution environment based on the skill.
  - Exploration report and snapshot files from `{PROJECT_ROOT}/.bridgic/explore/`
  - Work directory of the generated project from Phase 5
  - **Browser environment mode** from Phase 2: if **Isolated** mode is selected, pass `user-data-dir` = `{PROJECT_ROOT}/.bridgic/browser/`. The agent must override `user_data_dir` in the debug-instrumented code to this path. After verification is complete and all resources are cleaned up, **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** to leave a clean state.