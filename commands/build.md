---
description: >-
  End-to-end pipeline that turns any task into a working bridgic-amphibious
  project. TRIGGER when the user says like: "generate an amphibious project
  from this task" or "build a bridgic project", and does NOT specify a concrete
  domain command (e.g., not /build-browser). Users supply domain references —
  SKILLs, CLIs, SDK docs, style guides — and the command orchestrates: task
  initialization → pipeline configuration → environment setup → exploration →
  code generation → verification.
---

# Build Pipeline

Turn any task into a working bridgic-amphibious project. Domain-agnostic — users supply the domain-specific knowledge as references, and the pipeline handles the rest using the same methodology that `/build-browser` applies to the browser domain.

## Pipeline Workflow

```
1. Initialize Task          (this command — generate TASK.md template, user fills in task + domain references)
2. Configure Pipeline       (this command — project mode, LLM config if needed)
3. Setup Environment        (this command, runs setup-env.sh)
4. Exploration              (→ amphibious-explore agent)
5. Generate Amphibious Code (→ amphibious-code agent)
6. Verify                   (→ amphibious-verify agent)
```

> **Path variables**: `{PLUGIN_ROOT}` and `{PROJECT_ROOT}` are path placeholders — all paths below use these prefixes. If either is missing, the plugin was not loaded correctly — do not proceed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their task. Write the following template: `{PLUGIN_ROOT}/templates/build-task-template.md`. The template includes sections for *Task Description*, *Expected Output*, *Domain References*, and *Notes*. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill it in.

Wait for the user to confirm they have filled in the template. Then read `{PROJECT_ROOT}/TASK.md` and extract:

- **Task Description** — goal of the project.
- **Expected Output** — what indicates success.
- **Domain References** — list of paths to domain reference files (may be empty). Each entry may be a SKILL.md, CLI help dump, SDK doc, style guide, or any other material that teaches the agents *how to act* or *what rules to follow*. Resolve each path (relative paths resolve against `{PROJECT_ROOT}`) and confirm it exists. Any missing path is a validation error — ask the user to correct it before proceeding.
- **Notes** — optional additional constraints.

If Task Description or Expected Output is empty, ask the user to complete it before proceeding.

---

## Phase 2: Configure Pipeline

Present the following configuration questions **in order** as numbered choices. The user selects by entering the number (e.g., `1` or `2`). Wait for each answer before proceeding. All interactions with the user to confirm use `AskUserQuestion` to present the question and capture the answer.

### 2a. Project Mode

Present the options as:

> Choose project mode:
>
> **1. Workflow** — Every step runs deterministically. Best for stable, predictable tasks.
>
> **2. Amphiflow** — Every step runs normally, but switches to AI when something unexpected happens (unclear state, unrecoverable error, ambiguous branch). Requires LLM config.
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

3. **Task clearly does not require LLM** — The task is purely mechanical (deterministic file operations, fixed-shape API calls, scripted transformations). Skip LLM configuration entirely.

Record the **LLM configured** flag (yes/no) — it affects Phase 5.

Confirm understanding with the user (task summary from TASK.md + project mode + LLM configured) before proceeding.

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

Any additional domain-specific tool installation (e.g., installing a custom CLI, pulling an SDK) is deferred to Phase 4 — the `amphibious-explore` agent reads the user-supplied references (which typically include installation instructions) and sets up the execution environment as part of its own Domain Context phase.

---

## Phase 4: Exploration

**Delegate to the `amphibious-explore` agent.**

Pass to the agent:

- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - Output directory `{PROJECT_ROOT}/.bridgic/explore/`
- **Domain context** — the **Domain References** collected in Phase 1, forwarded unchanged:
  - Pass the absolute paths of every reference the user listed. Do not pre-distill them — the agent's own "Explore Domain Context" phase reads each reference through both operational and guidance lenses, derives the observation protocol and cleanup protocol, and extracts applicable directives.
  - If the user provided **no** references, state this explicitly in the domain context so the agent knows it must probe the environment from scratch using only the task description.

**Do not proceed to Phase 5 until exploration is complete.** The agent's output under `{PROJECT_ROOT}/.bridgic/explore/` (exploration report + artifact files) is the sole bridge between Phase 4 and Phase 5.

---

## Phase 5: Generate Amphibious Code

**Delegate to the `amphibious-code` agent.**

Pass to the agent:

- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - **LLM configured** from Phase 2 — whether LLM environment was validated (yes/no).
  - The exploration report path: `{PROJECT_ROOT}/.bridgic/explore/exploration_report.md` from Phase 4, plus any artifact files saved alongside it.
- **Domain context** — the **Domain References** from Phase 1, forwarded unchanged:
  - Pass the same reference paths to the agent. The agent factors them into per-file code generation (tool naming conventions, hook patterns, context-field declarations, main.py assembly patterns) in addition to its general per-file rules.
  - No pre-distilled per-file patterns are embedded in this command — `/build` is deliberately domain-agnostic. The authoritative domain signals for Phase 5 are: the exploration report's §1 *Domain Guidance* and the raw user references.

**Faithful to the exploration report** — `on_workflow` in `agents.py` must implement every numbered step (and sub-step) from the report's "Operation Sequence" — same order, same parameter values, same stability annotations. This requirement is pipeline-level, not domain-specific.

**Mode/LLM mapping** (the bridge from Phase 2 choices to `main.py`):
- **Project mode = Amphiflow** → pass `mode=RunMode.AMPHIFLOW` to `agent.arun()`; otherwise `mode=RunMode.WORKFLOW`.
- **LLM configured = yes** → initialize `OpenAILlm` from `config.py` / `.env` and pass `llm=llm` to the agent constructor.
- **LLM configured = no** → pass `llm=None`. Do not import or initialize any LLM classes.

---

## Phase 6: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent:

- **Task description** from Phase 1 (`TASK.md`)
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - Exploration report and artifact files from `{PROJECT_ROOT}/.bridgic/explore/`. Cross-check `on_workflow` against the report's "Operation Sequence" and treat any missing step as a bug to fix.
  - Work directory of the generated project from Phase 5.
- **Domain context** — the **Domain References** from Phase 1, forwarded unchanged:
  - The agent reads them to derive domain-specific success indicators and error patterns when validating results. No pre-distilled verification rules are embedded in this command.
