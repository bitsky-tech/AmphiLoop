---
description: >-
  End-to-end pipeline that turns any task into a working bridgic-amphibious
  project. TRIGGER when the user says like: "generate an amphibious project
  from this task" or "build a bridgic project". Optionally accepts a domain
  flag (e.g., `--browser`) to inject pre-distilled domain context. Without a
  flag, the model auto-detects the domain from TASK.md, falling back to a
  generic flow when no domain matches. Users may also supply additional
  domain references (SKILLs, CLIs, SDK docs, style guides) in TASK.md. The
  pipeline orchestrates: task initialization → pipeline configuration →
  environment setup → exploration → code generation → verification.
argument-hint: "[--<domain>]   e.g. --browser"
---

# Build Pipeline

Turn any task into a working bridgic-amphibious project. The pipeline is **domain-agnostic by default**, with optional **pre-distilled domain context** injected per supported domain (browser, ...).

## Argument parsing

`$ARGUMENTS` may be empty, or contain a single domain flag in either form `--<domain>` (e.g., `--browser`). Trim whitespace; ignore case.

- **Flag present** → set `SELECTED_DOMAIN = <domain>` and skip auto-detection. Validate that `{PLUGIN_ROOT}/domain-context/<domain>/` exists. If it does not, list the available domains (subdirectories of `{PLUGIN_ROOT}/domain-context/`) and ask the user to pick one or rerun without a flag.
- **No flag** → leave `SELECTED_DOMAIN` unresolved; resolve it during Phase 1's auto-detection step.

Anything else in `$ARGUMENTS` (extra tokens, multiple flags) → stop and ask the user to clarify.

## Pipeline Workflow

```
1. Initialize Task          (this command — generate TASK.md template, user fills in; then auto-detect domain if not flagged)
2. Configure Pipeline       (this command — generic config + domain config.md if any)
3. Setup Environment        (this command, runs setup-env.sh)
4. Exploration              (→ amphibious-explore agent)
5. Generate Amphibious Code (→ amphibious-code agent)
6. Verify                   (→ amphibious-verify agent)
```

> **Path variables**: `{PLUGIN_ROOT}` and `{PROJECT_ROOT}` are path placeholders — all paths below use these prefixes. If either is missing, the plugin was not loaded correctly — do not proceed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their task. Read the template from `{PLUGIN_ROOT}/templates/build-task-template.md` and write its contents verbatim to `{PROJECT_ROOT}/TASK.md`. The template includes sections for *Task Description*, *Expected Output*, *Domain References*, and *Notes*. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill it in.

Wait for the user to confirm. Then read `{PROJECT_ROOT}/TASK.md` and extract:

- **Task Description** — goal of the project.
- **Expected Output** — what indicates success.
- **Domain References** — list of paths to domain reference files (may be empty). Each entry may be a SKILL.md, CLI help dump, SDK doc, style guide, or any other material that teaches the agents *how to act* or *what rules to follow*. Resolve each path (relative paths resolve against `{PROJECT_ROOT}`) and confirm it exists. Any missing path is a validation error — ask the user to correct it before proceeding.
- **Notes** — optional additional constraints.

If Task Description or Expected Output is empty, ask the user to complete it before proceeding.

### Domain auto-detection (only if `SELECTED_DOMAIN` is unresolved)

1. List the subdirectories under `{PLUGIN_ROOT}/domain-context/`. Each subdirectory is a candidate domain.
2. For each candidate, read its `intent.md` (the matching criteria for that domain).
3. Compare the Task Description + Expected Output + Notes against each domain's `intent.md`. Pick the **single best match**, or `none` if no domain has strong signals.
4. If a candidate matches, present the decision via `AskUserQuestion`:

   > Detected domain: **<domain>**. Use the pre-distilled `<domain>` context for exploration, code generation, and verification?
   >
   > **1. Yes** — use `<domain>` context.
   > **2. No** — proceed with the generic (domain-agnostic) flow.
   > **3. Other** — let me name a different domain explicitly.

   On **1** set `SELECTED_DOMAIN = <domain>`. On **2** leave unresolved (generic flow). On **3** ask which domain (must match an existing subdirectory) and set accordingly.

5. If no candidate matches, do not ask — silently proceed with the generic flow (`SELECTED_DOMAIN` stays unresolved).

After this step `SELECTED_DOMAIN` is either a valid domain name or unresolved (generic).

---

## Phase 2: Configure Pipeline

Present configuration questions in order via `AskUserQuestion`. Wait for each answer before proceeding.

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

### 2b. Domain-specific configuration

If `SELECTED_DOMAIN` is resolved AND `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/config.md` exists, **read that file and follow its instructions** to ask any additional configuration questions for the chosen domain. Record each answer it asks you to record — these values will be forwarded as auxiliary context to Phases 4, 5, and 6.

If no `config.md` exists, skip this sub-step.

Confirm understanding with the user (task summary + project mode + LLM configured + any domain config answers) before proceeding.

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

Any additional domain-specific tool installation (e.g., installing a custom CLI, pulling an SDK) is deferred to Phase 4 — the `amphibious-explore` agent reads the domain context plus user-supplied references (which typically include installation instructions) and sets up the execution environment as part of its own **Analyse Task** phase.

---

## Phase 4: Exploration

**Delegate to the `amphibious-explore` agent.**

Pass to the agent:
- **Task description** 
  - from Phase 1 (`TASK.md`)
  - The **Domain References** from Phase 1.
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - Output directory `{PROJECT_ROOT}/.bridgic/explore/`
  - All values recorded by the domain `config.md` in Phase 2b (if any).
- **Domain context** — concatenation of:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/explore.md`.
  - **(else)** None (generic flow, no additional domain context).

**Do not proceed to Phase 5 until exploration is complete.** The agent's output under `{PROJECT_ROOT}/.bridgic/explore/` (exploration report + artifact files) is the sole bridge between Phase 4 and Phase 5.

---

## Phase 5: Generate Amphibious Code

**Delegate to the `amphibious-code` agent.**

Pass to the agent:
- **Task description** 
  - from Phase 1 (`TASK.md`)
  - The **Domain References** from Phase 1.
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - **LLM configured** from Phase 2 — whether LLM environment was validated (yes/no).
  - All values recorded by the domain `config.md` in Phase 2b (if any).
  - The exploration report path: `{PROJECT_ROOT}/.bridgic/explore/exploration_report.md` from Phase 4, plus any artifact files saved alongside it.
- **Domain context** — concatenation of:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/code.md`. 
  - **(else)** None (generic flow, no additional domain context).

**Mode/LLM mapping** (the bridge from Phase 2 choices to `main.py`):
- **Project mode = Amphiflow** → pass `mode=RunMode.AMPHIFLOW` to `agent.arun()`; otherwise `mode=RunMode.WORKFLOW`.
- **LLM configured = yes** → initialize `OpenAILlm` from `config.py` / `.env` and pass `llm=llm` to the agent constructor.
- **LLM configured = no** → pass `llm=None`. Do not import or initialize any LLM classes.

---

## Phase 6: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent:
- **Task description** 
  - from Phase 1 (`TASK.md`)
  - The **Domain References** from Phase 1
- **Auxiliary context**:
  - `PLUGIN_ROOT` and `PROJECT_ROOT` values
  - **Project mode** from Phase 2 — **Workflow** or **Amphiflow**
  - All values recorded by the domain `config.md` in Phase 2b (if any).
  - Exploration report and artifact files from `{PROJECT_ROOT}/.bridgic/explore/`. Cross-check `on_workflow` against the report's "Operation Sequence" and treat any missing step as a bug to fix.
  - Work directory of the generated project from Phase 5.
- **Domain context** — concatenation of:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/verify.md`.
  - **(else)** None (generic flow, no additional domain context).
