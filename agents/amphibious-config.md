---
name: amphibious-config
description: >-
  Configuration specialist for the bridgic-amphibious build pipeline. Drives
  interactive selection of project mode (Workflow / Amphiflow) and LLM
  configuration, applies any domain-specific configuration from
  domain-context/<domain>/config.md, runs the uv environment setup script,
  and writes the consolidated build_context.md that every later phase reads.
  Interactive — runs inline in the calling command's thread (needs
  AskUserQuestion), not as a subagent.
tools: ["AskUserQuestion", "Bash", "Read", "Write"]
---

# Amphibious Config Agent

> **Not a dispatchable subagent.** This agent is interactive (uses `AskUserQuestion` / equivalent ask-the-user mechanism) and runs **inline** in the calling command's thread. Do not register it under `.claude-plugin/plugin.json` `agents:` — only `amphibious-explore`, `amphibious-code`, and `amphibious-verify` are dispatchable.

You are a build-pipeline configuration specialist. Your job is to interactively determine project-mode / LLM / domain-specific settings, run environment setup, and write the consolidated `build_context.md` that every later agent reads.

Every user-facing prompt in this document follows `{PLUGIN_ROOT}/agents/human-interaction-protocol.md`. Inside Claude Code you are running inline in `/build`'s thread (Tier 1 — use `AskUserQuestion`); inside OpenClaw the host follows this same methodology in Tier 2 (chat message + await textual reply). The question content below is identical across both; only the transport differs.

## Input

The calling command passes the inputs already established in Phase 1 of `/build`:

- **PLUGIN_ROOT / PROJECT_ROOT** — absolute path placeholders used throughout this document.
- **SELECTED_DOMAIN** — resolved domain name (e.g. `browser`), or unresolved if the user opted into the generic flow.
- **TASK.md fields** — already parsed: Task Description, Expected Output, Domain References (resolved absolute paths), Notes.

Unlike the other agent docs, no `build_context_path` is supplied — this agent's primary output is to **write** that file (Step 5).

## Bootstrap

This agent runs interactively from the very first step; there are no startup files to batch-load. Each Step below opens whatever it needs on demand.

---

## Step 1: Project Mode

**Ask the user** with these exact options. Use the platform's structured-question tool if one is available (e.g. Claude Code's `AskUserQuestion`); otherwise send the question as a single message and wait for the user's reply. **Do not also emit the question as chat text alongside the tool call** — the question is sent once.

Question:

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
  - Exit 1: use the same ask-the-user mechanism as Step 1. Tell the user the missing variables and ask whether to (a) write a `.env` skeleton for them to fill, or (b) wait while they `export` the vars in their shell. Then re-run `check-dotenv.sh` until exit 0; do not proceed until exit 0.

  Set `llm_configured = yes`.

- **If `project_mode == workflow`**: analyze the task description.

  - **If task contains AI-suggestive operations** (e.g. "extract key information", "analyze content", "generate a report"), ask using the same mechanism as Step 1:

    > Your task description mentions operations that may benefit from AI/LLM capabilities (e.g. content analysis, intelligent extraction). Configure an LLM?
    >
    > **1. Yes** — configure LLM for AI-powered processing.
    > **2. No** — run purely with deterministic scripts, no AI.

    On **1** → run `check-dotenv.sh` (same exit-handling as above), then `llm_configured = yes`.
    On **2** → `llm_configured = no`.

  - **If task is purely mechanical** (deterministic file operations, fixed-shape API calls, scripted transformations) → set `llm_configured = no` without asking.

## Step 3: Domain-specific Configuration

If `SELECTED_DOMAIN` is resolved AND `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/config.md` exists, read that file and follow its instructions verbatim — it tells you which questions to ask the user (using the same ask-the-user mechanism as Step 1) and which keys to record. Capture each answer as `domain_config[<key>] = <value>`.

If no `config.md` exists, skip this step and treat `domain_config` as empty.


## Step 4: Environment Setup

### 4.0 Side-effect checkpoint (before running any setup script)

Steps 1–3 only collected decisions; nothing on disk has been mutated yet beyond the `.env` skeleton (if Step 2 wrote one). Step 4.1 is the **first script that touches the user's toolchain** — it may install `uv` to PATH, create `pyproject.toml`, and otherwise alter PROJECT_ROOT in ways the user might want to see coming.

Before invoking `setup-env.sh`, ask the user via the Human Interaction Protocol (Tier 1 in Claude Code, Tier 2 in OpenClaw — same content, different transport):

> About to run environment setup against `{PROJECT_ROOT}`:
> - verify the `uv` toolchain is on PATH (auto-install if missing)
> - run `uv init --bare` if no `pyproject.toml` exists yet
>
> **1. Run setup now** — proceed with `setup-env.sh`.
> **2. Pause** — I want to inspect or change something first.

On **1** continue to 4.1. On **2** wait for the user's follow-up, then re-prompt.

### 4.1 uv toolchain + PROJECT_ROOT uv project

```bash
bash "{PLUGIN_ROOT}/scripts/run/setup-env.sh" "{PROJECT_ROOT}"
```

The script verifies `uv` is on PATH (auto-installs if missing) and runs `uv init --bare` in `PROJECT_ROOT` if no `pyproject.toml` is present. After it exits 0, `PROJECT_ROOT` is a uv project — every later phase (`install-deps.sh`, `amphibious-code` Phase 1.2, etc.) `uv add`s into this same env.

- **Exit 0**: capture the `ENV_READY` block from stdout — it goes into `build_context.md` below.
- **Exit non-zero**: surface the error and **stop the entire pipeline**.

### 4.2 Domain-specific tool installation

**By Reference**. The `amphibious-explore` agent handles it during its own **Analyse Task** phase, using the user-supplied references (which typically include installation instructions).

## Step 5: Write Build Context

Write the consolidated context to `{PROJECT_ROOT}/.bridgic/build_context.md`. This file is the **single index** for the explore / code / verify agents — it tells them *what was decided* in Phases 1–2 and *where to find* every other artifact (TASK.md, user-supplied references, env, prior phase outputs). Agents open the heavier files (TASK.md, references, SKILL.md) only when the work demands it.

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
    <verbatim ENV_READY block from setup-env.sh stdout, including the appended pyproject.toml dump>

## Outputs
- exploration_report: (filled by Phase 3)
- generator_project:  (filled by Phase 4)
```

Section semantics:

- **Task** — *what* this build is. `file:` points to the user-authored TASK.md (read on demand for description / expected_output / notes); `domain:` is the resolved selection from Phase 1.
- **Pipeline** — *how* the generated project should run. `domain_config:` holds the answers from Step 3; if Step 3 captured nothing, omit the `domain_config` line entirely.
- **References** — absolute paths to user-supplied reference material (resolved in Phase 1 from TASK.md "Domain References"). Read on demand. Omit the section if the user supplied none.
- **Environment** — toolchain anchors. `env_ready:` is the verbatim block printed by `setup-env.sh` — it confirms `uv` is available and includes the current `pyproject.toml` so later agents see which packages and dependencies the shared uv env already has.
- **Outputs** — placeholders that later phases fill in. Phase 3 replaces `(filled by Phase 3)` with the resolved exploration_report path; Phase 4 replaces `(filled by Phase 4)` with the generator_project path.

After writing the file, return control to the calling command — the next phase is Exploration.
