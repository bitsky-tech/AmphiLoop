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

## Agent invocation contract

Phases 3, 4, and 5 each delegate to a subagent. **Every delegation passes exactly two absolute paths**:

- **build_context_path** — always `{PROJECT_ROOT}/.bridgic/build_context.md`.
- **domain_context_path** — `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/<phase>.md` when `SELECTED_DOMAIN` is resolved, otherwise the literal `none` (generic flow). `<phase>` is `explore.md` for Phase 3, `code.md` for Phase 4, `verify.md` for Phase 5.

After Phases 3 and 4, **append** the agent's primary output path to `build_context.md`'s `## Outputs` section by replacing the matching `(filled by Phase N)` placeholder.

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
4. Environment Setup (`setup-env.sh` — verifies `uv` toolchain only; the per-project `uv init` happens later inside `<project-name>/`)
5. Write `{PROJECT_ROOT}/.bridgic/build_context.md` (the single source of truth for Phases 3–5)

If `setup-env.sh` exits non-zero, the methodology doc says to **stop the entire pipeline** — respect that and do not enter Phase 3.

On successful completion, `{PROJECT_ROOT}/.bridgic/build_context.md` exists and is the only artifact later phases need to read for context.

---

## Phase 3: Exploration

Delegate to **`amphibious-explore`** (per Agent invocation contract). Do not start Phase 4 until exploration is complete — the report and artifact files under `{PROJECT_ROOT}/.bridgic/explore/` are the sole bridge between Phase 3 and Phase 4. After the agent returns, fill `## Outputs → exploration_report` in `build_context.md`.

---

## Phase 4: Generate Amphibious Code

Delegate to **`amphibious-code`** (per Agent invocation contract).

**Mode / LLM mapping** (Phase 2 choices → `main.py`):
- Project mode = Amphiflow → `mode=RunMode.AMPHIFLOW`; Workflow → `mode=RunMode.WORKFLOW`.
- LLM configured = yes → initialise `OpenAILlm` inline in `main.py` from `os.getenv` (after `load_dotenv()`) and pass `llm=llm`.
- LLM configured = no → pass `llm=None`. Do not import any LLM class.

After the agent returns, fill `## Outputs → generator_project` (the `<PROJECT_ROOT>/<project-name>/` subdirectory the agent created and populated) in `build_context.md`.

---

## Phase 5: Verify

Immediately delegate to **`amphibious-verify`** (per Agent invocation contract). Cross-check `on_workflow` against the exploration report's "Operation Sequence" — any missing step is a bug to fix.
