# Amphibious Config — Inline Methodology

This document defines the **Configure & Setup** phase: project-mode selection, LLM configuration, optional domain-specific configuration, environment initialization (`uv` project), and writing the consolidated `build_context.md` that all later agents read.

## Inputs

- `PLUGIN_ROOT` — absolute path to the plugin root.
- `PROJECT_ROOT` — absolute path to the user's working directory.
- `SELECTED_DOMAIN` — domain name (e.g. `browser`) or unresolved (generic flow).
- TASK.md content already extracted: Task Description, Expected Output, Domain References (resolved absolute paths), Notes.

## Step 1: Project Mode

Present via `AskUserQuestion`:

> Choose project mode:
>
> **1. Workflow** — Every step runs deterministically. Best for stable, predictable tasks.
>
> **2. Amphiflow** — Every step runs normally, but switches to AI when something unexpected happens (unclear state, unrecoverable error, ambiguous branch). Requires LLM config.

Record the chosen `project_mode` (`workflow` or `amphiflow`). It will determine the `mode=` argument passed to `agent.arun()` during code generation (Phase 4 of `/build`).

## Step 2: LLM Configuration

Decide whether to set up LLM — set `llm_configured` to `yes` or `no`.

- **If `project_mode == amphiflow`**: LLM is required. Run

  ```bash
  bash "{PLUGIN_ROOT}/scripts/run/check-dotenv.sh"
  ```

  - Exit 0: variables present — proceed.
  - Exit 1: list missing variables; create `.env`, ask the user to fill it, re-run the check; do not proceed until exit 0.

  Set `llm_configured = yes`.

- **If `project_mode == workflow`**: analyze the task description.

  - **If task contains AI-suggestive operations** (e.g. "extract key information", "analyze content", "generate a report"), ask via `AskUserQuestion`:

    > Your task description mentions operations that may benefit from AI/LLM capabilities (e.g. content analysis, intelligent extraction). Configure an LLM?
    >
    > **1. Yes** — configure LLM for AI-powered processing.
    > **2. No** — run purely with deterministic scripts, no AI.

    On **1** → run `check-dotenv.sh` (same exit-handling as above), then `llm_configured = yes`.
    On **2** → `llm_configured = no`.

  - **If task is purely mechanical** (deterministic file operations, fixed-shape API calls, scripted transformations) → set `llm_configured = no` without asking.

## Step 3: Domain-specific Configuration

If `SELECTED_DOMAIN` is resolved AND `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/config.md` exists, read that file and follow its instructions verbatim — it tells you which questions to ask the user (still via `AskUserQuestion`) and which keys to record. Capture each answer as `domain_config[<key>] = <value>`.

If no `config.md` exists, skip this step and treat `domain_config` as empty.


## Step 4: Environment Setup

Two checks happen here; both must pass before Step 5.

### 4.1 uv toolchain

```bash
bash "{PLUGIN_ROOT}/scripts/run/setup-env.sh"
```

Verifies `uv` is on PATH (auto-installs it if missing). PROJECT_ROOT itself is **not** a uv project — the actual uv project is initialised inside the generated `<project-name>/` subdirectory by the `amphibious-code` agent during Phase 4 of `/build`.

- **Exit 0**: capture the `ENV_READY` block from stdout — it goes into `build_context.md` below.
- **Exit non-zero**: surface the error and **stop the entire pipeline**.

### 4.2 Private package index (`BRIDGIC_DEV_INDEX`)

The bridgic-amphibious skill's `deps.ini` pins `bridgic-amphibious` to a private index named `btsk-repo`; its installer (`install-deps.sh`, called later by `amphibious-code`) resolves that name to the URL held in the `BRIDGIC_DEV_INDEX` env var. Without it, dependency installation in Phase 4 fails with `dev_index_missing`.

Check whether it is set:

```bash
[ -n "${BRIDGIC_DEV_INDEX:-}" ] && echo "set" || echo "missing"
```

If missing, ask the user to set it before continuing — typically by exporting it in their shell rc file (`~/.zshrc` / `~/.bashrc`) so future `/build` runs inherit it automatically:

```bash
export BRIDGIC_DEV_INDEX="<URL of the private index>"
```

Wait for the user to confirm and re-check `${BRIDGIC_DEV_INDEX:-}` in this thread before proceeding to Step 5.

### 4.3 Domain-specific tool installation

Not done here. The `amphibious-explore` agent handles it during its own **Analyse Task** phase, using the user-supplied references (which typically include installation instructions).

## Step 5: Write Build Context

Write the consolidated context to `{PROJECT_ROOT}/.bridgic/build_context.md`. This file is the **single index** for the explore / code / verify agents — it tells them *what was decided* in Phases 1–2 and *where to find* every other artifact (TASK.md, reference docs, skills, env, prior phase outputs). Agents open the heavier files (TASK.md, references, SKILL.md) only when the work demands it.

Use this exact structure (omit any section whose body would be empty):

```markdown
# Build Context

## Task
- file: {PROJECT_ROOT}/TASK.md
- domain: <browser | none>

## Pipeline
- mode: <workflow | amphiflow>
- llm_configured: <yes | no>
- domain_config:
    <key>: <value>

## References
- <absolute path>

## Environment
- plugin_root: {PLUGIN_ROOT}
- project_root: {PROJECT_ROOT}
- env_ready: |
    <verbatim ENV_READY block from setup-env.sh stdout>

## Outputs
- exploration_report: (filled by Phase 3)
- generator_project:  (filled by Phase 4)
```

Section semantics:

- **Task** — *what* this build is. `file:` points to the user-authored TASK.md (read on demand for description / expected_output / notes); `domain:` is the resolved selection from Phase 1.
- **Pipeline** — *how* the generated project should run. `domain_config:` holds the answers from Step 3; if Step 3 captured nothing, omit the `domain_config` line entirely.
- **References** — absolute paths to user-supplied reference material (resolved in Phase 1 from TASK.md "Domain References"). Read on demand. Omit the section if the user supplied none.
- **Environment** — toolchain anchors. `env_ready:` is the verbatim block printed by `setup-env.sh`. `skills:` lists framework-skill pointers; agents read them on demand.
- **Outputs** — placeholders that later phases fill in. Phase 3 replaces `(filled by Phase 3)` with the resolved exploration_report path; Phase 4 replaces `(filled by Phase 4)` with the generator_project path.

After writing the file, return control to the calling command — the next phase is Exploration.
