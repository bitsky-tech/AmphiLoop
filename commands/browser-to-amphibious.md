---
description: >-
  End-to-end pipeline that turns a browser automation task into a working
  bridgic-amphibious project. TRIGGER when the user: (1) provides a browser
  task and wants to generate an amphibious project from it, (2) says things
  like "把这个浏览器任务转成代码", "帮我生成自动化项目", "从网页操作生成
  amphibious 代码", "turn this browser task into code", "generate a project
  from this browser workflow", or (3) wants to explore a website via CLI and
  then produce a bridgic-amphibious codebase. The pipeline covers: CLI
  exploration → SDK code generation → verification.
---

# Browser-to-Amphibious Pipeline

Turn a browser task into a working bridgic-amphibious project:
CLI exploration → SDK code generation → verification.

## Pipeline Graph

```
/browser-to-amphibious (command)
    │
    ├── runs: setup-env.sh (script)
    │
    ├── delegates to: browser-explorer (agent)
    │     └── reads from: bridgic-browser (skill)
    │
    ├── delegates to: amphibious-generator (agent)
    │     ├── reads from: bridgic-amphibious (skill)
    │     ├── reads from: bridgic-llms (skill)
    │     │
    │     └── receives domain context from this command:
    │           ├── bridgic-browser (skill)
    │           └── browser-code-patterns.md
    │
    └── delegates to: amphibious-verify (agent)
          └── receives domain context: browser verification rules
```

## Pipeline Workflow

```
1. Parse Task Input         (this command)
2. Setup Environment        (this command, runs setup-env.sh)
3. CLI Exploration          (→ browser-explorer agent)
4. Generate Amphibious Code (→ amphibious-generator agent)
5. Verify                   (→ amphibious-verify agent)
```

---

## Phase 1: Parse Task Input

Accept the browser task from the user (direct string or file path). Extract:
- **Target URL(s)**
- **Goal** — what the automation accomplishes
- **Expected output** — data to extract or actions to complete
- **Browser environment mode** — ask the user:

### Browser Environment Mode

> Do you want each pipeline phase to use an **isolated** browser profile, or is **quick** mode (shared default profile) fine?

| Mode | Behavior |
|------|----------|
| **Quick** (default) | No `user-data-dir` overrides — all phases share the browser's default profile. Faster, reuses existing cookies/sessions. |
| **Isolated** | Each phase gets its own `user-data-dir`, ensuring a clean browser state per phase. Useful when login state or cookies from one phase must not leak into another. |

Record the chosen mode — it affects Phases 3, 4, and 5.

Confirm understanding with the user before proceeding.

---

## Phase 2: Setup Environment

Two independent checks — run in order:

### 2a. Virtual environment

```bash
bash "scripts/run/setup-env.sh"
```

Handles: uv check → pyproject.toml creation → `uv sync` → Playwright Chromium install.

- **Exit 0**: dependencies ready. Capture the `ENV_READY` block from stdout.
- **Exit 1**: `uv` not installed. Tell the user to install it and stop.

### 2b. Model configuration

```bash
bash "scripts/run/check-dotenv.sh"
```

Validates `LLM_API_KEY`, `LLM_API_BASE`, `LLM_MODEL` are available (from environment variables or `.env` file). Never prints values.

- **Exit 0**: all variables present.
- **Exit 1**: missing variables listed in output. Ask the user to provide them, then re-run.

Capture the `ENV_READY` block from setup-env.sh as the environment details passed to later phases. Do not proceed until both scripts exit 0.

---

## Phase 3: CLI Exploration

**Delegate to the `browser-explorer` agent.**

Pass to the agent:
- **Task description** from Phase 1
- **Auxiliary context**: Output directory `.bridgic/explore/` (for exploration report and snapshot files), plus environment details from Phase 2
  - **If Isolated mode**: also pass `user-data-dir` = `.bridgic/explore/browser`. The agent must create this directory and pass `--user-data-dir .bridgic/explore/browser` to all `bridgic-browser` CLI invocations, ensuring exploration runs in a clean browser profile.

**Do not proceed to Phase 4 until complete.**

---

## Phase 4: Generate Amphibious Code

**Delegate to the `amphibious-generator` agent.**

Pass to the agent:
- **Task description** from Phase 1
- **Auxiliary context**: Include the exploration report (`.bridgic/explore/exploration_report.md`) and snapshot file paths from Phase 3, plus environment details from Phase 2 (e.g., LLM model, API base)
- **Domain context** (browser automation): Include the following browser-specific instructions in the delegation prompt:

### Domain Context to Pass

**Domain reference files to read**:
- `bridgic-browser` skill — `references/sdk-guide.md` and `references/cli-sdk-api-mapping.md` for SDK tool names and usage
- `commands/references/browser-code-patterns.md` — browser-specific code patterns for all project files

**Browser-specific per-file rules** (override or supplement the agent's general rules):

#### agents.py

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
- **`after_action` hook (MUST override)**: refresh `ctx.observation` after `wait_for` completes. Without this, inline code between a `wait_for` yield and the next yield sees stale (pre-wait) page state. See `browser-code-patterns.md` for the mandatory code pattern and optional additional uses.

#### workers.py

- The `browser` field must be marked `json_schema_extra={"display": False}` — serializing a browser instance is meaningless.
- State-tracking fields (e.g., scraped item sets, counters) should remain visible.

#### helpers.py

- Extraction functions parse live `ctx.observation` at runtime. To **write** these helpers, read the snapshot files in `.bridgic/explore/` (referenced in the exploration report) for the real a11y tree structure. Do not guess the format.

#### main.py

- **Browser lifecycle**: `async with Browser() as browser` — create in main.py, store in context.
  - **If Isolated mode**: set `user_data_dir` to `.bridgic/browser` so the generated project runs in its own clean browser profile.
  - **If Quick mode**: omit `user_data_dir` (use the browser's default profile).
- **Browser tools**: `BrowserToolSetBuilder.for_tool_names(browser, ...)` selecting only the SDK methods used in the exploration.
- **Tool assembly**: `[*browser_tools, *task_tools]` → pass to `agent.arun(tools=all_tools)`.

The agent will:
1. Scaffold the project via `bridgic-amphibious create`
2. Load framework references from `bridgic-amphibious` skill + browser domain references from above
3. Complete all project files based on the scaffold created by `bridgic-amphibious create`.

**Proceed directly to Phase 5**. Code quality issues are the sole responsibility of the amphibious-verify agent — it will run the project, detect errors from actual execution, and fix them with proper diagnosis.

---

## Phase 5: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent:
- **Task description** from Phase 1
- **Auxiliary context**: Exploration report and snapshot files from `.bridgic/explore/`, plus the work directory of the generated project from Phase 4
  - **If Isolated mode**: also pass `user-data-dir` = `.bridgic/verify/browser`. The agent must override `user_data_dir` in the debug-instrumented code to this path, ensuring verification runs in a browser profile separate from both exploration and the generated project.