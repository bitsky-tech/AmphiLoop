---
description: >-
  End-to-end pipeline that turns any task into a working bridgic-amphibious
  project. TRIGGER when the user says like: "generate an amphibious project
  from this task" or "build a bridgic project". Optionally accepts a domain
  flag (e.g., `--browser`) to inject pre-distilled domain context. Without a
  flag, the model auto-detects the domain from TASK.md, falling back to a
  generic flow when no domain matches. Users may also supply additional
  domain references (SKILLs, CLIs, SDK docs, style guides) in TASK.md. The
  pipeline orchestrates: task initialization → configure & setup →
  exploration → code generation → verification.
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
2. Configure & Setup        (this command — user interactions; writes build_context.md)
3. Exploration              (→ amphibious-explore agent)
4. Generate Amphibious Code (→ amphibious-code agent)
5. Verify                   (→ amphibious-verify agent)
```

> **Path variables**: `{PLUGIN_ROOT}` and `{PROJECT_ROOT}` are path placeholders — all paths below use these prefixes. If either is missing, the plugin was not loaded correctly — do not proceed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their task. Read the template from `{PLUGIN_ROOT}/templates/build-task-template.md` and write its contents verbatim to `{PROJECT_ROOT}/TASK.md`. The template includes sections for *Task Description*, *Expected Output*, *Domain References*, and *Notes*. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill it in.

Wait for the user to confirm. Then read `{PROJECT_ROOT}/TASK.md` and understand:

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

## Phase 2: Configure & Setup

**Execute yourself** by reading `{PLUGIN_ROOT}/agents/amphibious-config.md` and following its steps in order, in this thread, with the inputs already established in Phase 1 (`PLUGIN_ROOT`, `PROJECT_ROOT`, `SELECTED_DOMAIN`, and the parsed TASK.md fields).

The methodology document covers, in this order:

1. Project Mode (Workflow | Amphiflow)
2. LLM Configuration (`check-dotenv.sh`)
3. Domain-specific Configuration (`domain-context/<domain>/config.md`, if any)
4. Environment Setup (`setup-env.sh` → `uv init`)
5. Write `{PROJECT_ROOT}/.bridgic/build_context.md` (the single source of truth for Phases 3–5)

If `setup-env.sh` exits non-zero, the methodology doc says to **stop the entire pipeline** — respect that and do not enter Phase 3.

On successful completion, `{PROJECT_ROOT}/.bridgic/build_context.md` exists and is the only artifact later phases need to read for context.

---

## Phase 3: Exploration

**Delegate to the `amphibious-explore` agent.**

Pass to the agent **exactly two inputs**:

- **build_context_path**: `{PROJECT_ROOT}/.bridgic/build_context.md`
- **domain_context_path**:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/explore.md`.
  - **(else)** `none` (generic flow).

**Do not proceed to Phase 4 until exploration is complete.** The agent's output under `{PROJECT_ROOT}/.bridgic/explore/` (exploration report + artifact files) is the sole bridge between Phase 3 and Phase 4.

After the agent returns, **append** the resolved exploration_report path to `build_context.md`'s `## Outputs` section by replacing the `(filled by Phase 3)` placeholder.

---

## Phase 4: Generate Amphibious Code

**Delegate to the `amphibious-code` agent.**

Pass to the agent **exactly two inputs**:

- **build_context_path**: `{PROJECT_ROOT}/.bridgic/build_context.md`
- **domain_context_path**:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/code.md`.
  - **(else)** `none` (generic flow).

**Mode/LLM mapping** (the bridge from Phase 2 choices to `main.py`):
- **Project mode = Amphiflow** → pass `mode=RunMode.AMPHIFLOW` to `agent.arun()`; otherwise `mode=RunMode.WORKFLOW`.
- **LLM configured = yes** → initialize `OpenAILlm` inline in `main.py` from `os.getenv` (after `load_dotenv()`) and pass `llm=llm` to the agent constructor.
- **LLM configured = no** → pass `llm=None`. Do not import or initialize any LLM classes.

After the agent returns, **append** the resolved generator-project path (the `<PROJECT_ROOT>/<project-name>/` subdirectory the agent created and populated) to `build_context.md`'s `## Outputs` section by replacing the `(filled by Phase 4)` placeholder.

---

## Phase 5: Verify

**Immediately delegate to the `amphibious-verify` agent.**

Pass to the agent **exactly two inputs**:

- **build_context_path**: `{PROJECT_ROOT}/.bridgic/build_context.md`
- **domain_context_path**:
  - **(if `SELECTED_DOMAIN` is resolved)** the absolute path of `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/verify.md`.
  - **(else)** `none` (generic flow).

Cross-check `on_workflow` against the exploration report's "Operation Sequence" and treat any missing step as a bug to fix.
