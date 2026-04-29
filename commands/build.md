---
description: >-
  End-to-end pipeline that turns any task into a working bridgic-amphibious
  project. TRIGGER when the user invokes the build slash command
  (`/AmphiLoop:build` on Claude Code, `/amphi-build` on Hermes) or asks to
  "generate an amphibious project from this task" / "build a bridgic project".
  Optionally accepts a domain flag (e.g., `--browser`) to inject pre-distilled
  domain context. Without a flag, the model auto-detects the domain from
  TASK.md, falling back to a generic flow when no domain matches. Users may
  also supply additional domain references (SKILLs, CLIs, SDK docs, style
  guides) in TASK.md. The pipeline orchestrates: Phase 0 path binding →
  Phase 1 task initialization → Phase 2 configure & setup → Phase 3
  exploration → Phase 4 code generation → Phase 5 verification.
argument-hint: "[--<domain>]   e.g. --browser"
---

# Build Pipeline

Turn any task into a working bridgic-amphibious project. The pipeline is **domain-agnostic by default**, with optional **pre-distilled domain context** injected per supported domain (browser, ...).

This skill runs on **two host runtimes** — Claude Code and Hermes Agent. The control flow, phase contracts, and on-disk artifacts are identical; only a handful of mechanics differ:

| Concern | Claude Code | Hermes |
|---|---|---|
| Slash command | `/AmphiLoop:build` | `/amphi-build` |
| Args carrier | `$ARGUMENTS` (expanded inline) | raw args passed to the `/amphi-build` handler |
| User clarification | `AskUserQuestion` tool | `clarify` tool |
| Path binding | hook-injected `additionalContext` block | activation `[Skill directory: …]` line + ask user |
| Subagent dispatch | Task tool with `subagent_type: "amphibious-<phase>"` | `delegate_task(...)` + `skill_view("amphi-loop:amphibious-<phase>")` |

Throughout this document, **"ask the user"** means use the host's clarification tool above; **"delegate to the X agent"** means use the host's subagent dispatch above. Everything else (file paths, control flow, agent contracts) is platform-neutral.

---

## Phase 0: Resolve workspace paths (mandatory pre-flight)

The pipeline writes several files (`TASK.md`, `.bridgic/build_context.md`, generated project tree) — `PLUGIN_ROOT` and `PROJECT_ROOT` must be bound to absolute paths **before any other phase**. **If either cannot be resolved, stop immediately** — do not proceed with relative-path guesses.

### 0a. Bind `PLUGIN_ROOT` and `PROJECT_ROOT` per host runtime

**On Claude Code** — the plugin's `inject-command-paths.sh` hook attaches an `additionalContext` block containing two real lines of the form `PLUGIN_ROOT=/...` and `PROJECT_ROOT=/...` (note the leading `/` — actual absolute paths, NOT the literal `<...>` placeholder used in this prose). Bind both variables from those lines and skip 0b entirely.

**On Hermes** — the activation message ends with a real line of the form `[Skill directory: /…]`. Bind `PLUGIN_ROOT` to that path. `PROJECT_ROOT` is not auto-injected — proceed to 0b to confirm it interactively.

If neither marker is present (e.g. the skill was loaded outside the normal `/AmphiLoop:build` / `/amphi-build` flow), bind `PLUGIN_ROOT` to the absolute path containing `templates/build-task-template.md` and `scripts/run/setup-env.sh` (`~/.claude/plugins/AmphiLoop` for a default Claude Code install; `~/.hermes/plugins/amphi-loop` for a default Hermes install). If that also fails, stop and report — the plugin is not loaded correctly.

### 0b. Confirm `PROJECT_ROOT` (Hermes only — interactive)

Skip this section entirely if `PROJECT_ROOT` was already bound from the Claude Code hook in 0a.

Compute the candidate working directory:

```bash
pwd
```

Then ask the user:

- **question**: `I'll use this directory as the project root for the entire pipeline (TASK.md, .bridgic/, generated project tree, run logs, results all go here): <pwd output>. Continue here, or specify a different path?`
- **choices**: `["Yes — use this directory", "No — I'll provide an absolute path"]`

On **Yes**, bind `PROJECT_ROOT` to the `pwd` value.
On **No** (or "Other" with a typed path), ask again (open-ended) for the absolute path, then verify with `[ -d "<path>" ]`. If it does not exist, ask whether to create it (`mkdir -p <path>`) or pick a different one. Only bind `PROJECT_ROOT` after the directory exists on disk.

### 0c. Confirmation

Echo the final binding to the user:

> ✓ Workspace paths bound:
> - `PLUGIN_ROOT` = `<resolved>`
> - `PROJECT_ROOT` = `<resolved>`

Every reference below to `{PLUGIN_ROOT}/...` and `{PROJECT_ROOT}/...` means these resolved absolute paths. Do not re-derive them in later phases.

---

## Argument parsing

The slash command's input may be empty or contain a single domain flag in either form `--<domain>` (e.g., `--browser`). The carrier is `$ARGUMENTS` on Claude Code and the raw args string handed to the `/amphi-build` handler on Hermes. Trim whitespace; ignore case.

- **Flag present** → set `SELECTED_DOMAIN = <domain>` and skip auto-detection. Validate that `{PLUGIN_ROOT}/domain-context/<domain>/` exists. If it does not, list the available domains (subdirectories of `{PLUGIN_ROOT}/domain-context/`) and ask the user to pick one or rerun without a flag.
- **No flag** → leave `SELECTED_DOMAIN` unresolved; resolve it during Phase 1's auto-detection step.

Anything else in the input (extra tokens, multiple flags) → stop and ask the user to clarify.

## Pipeline Workflow

```
0. Resolve workspace paths  (this skill — bind PLUGIN_ROOT + PROJECT_ROOT)
1. Initialize Task          (this skill — generate TASK.md template, user fills in; then auto-detect domain if not flagged)
2. Configure & Setup        (this skill — load amphibious-config methodology; writes build_context.md)
3. Exploration              (→ amphibious-explore agent — subagent)
4. Generate Amphibious Code (→ amphibious-code agent — subagent)
5. Verify                   (→ amphibious-verify agent — subagent)
```

> **Why subagents for 3/4/5?** Each phase produces a large transient context (probe outputs, codegen drafts, verify retries). Running them inline collapses everything into the orchestrator's context window and quickly hits the limit. A fresh subagent per phase keeps only the final summary in this skill's context.

---

## Agent invocation contract (Phases 3, 4, 5)

Every Phase 3/4/5 dispatch passes **exactly two absolute paths** in the subagent's context:

- **build_context_path** — always `{PROJECT_ROOT}/.bridgic/build_context.md`. The single source of truth for everything decided in Phases 1–2 (task brief location, mode, llm_configured, references, env_ready snapshot, prior phase outputs).
- **domain_context_path** — `{PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/<phase>.md` when `SELECTED_DOMAIN` is resolved, otherwise the literal string `none`. `<phase>` is `explore.md` for Phase 3, `code.md` for Phase 4, `verify.md` for Phase 5.

After Phases 3 and 4, refresh `{PROJECT_ROOT}/.bridgic/build_context.md` in two places:

1. **Outputs** — replace the matching `(filled by Phase N)` placeholder with the agent's primary output path.
2. **env_ready** — read `{PROJECT_ROOT}/pyproject.toml` and update the dump under `--- pyproject.toml ---` inside the `env_ready:` block with its current contents.

This is what every subagent reads — keep it accurate.

### Subagent dispatch — per host runtime

**On Claude Code** — delegate to the agent by name via the Task tool with `subagent_type` set to `amphibious-explore` / `amphibious-code` / `amphibious-verify`. The two paths above go into the subagent's prompt verbatim. The agent file's frontmatter (`tools: [...]`) restricts what the subagent can do — notably, it has no `AskUserQuestion`. If a clarification is genuinely needed, the subagent must return early with a precise question for this orchestrator to ask.

**On Hermes** — call `delegate_task` with the goal/toolsets/context shaped per phase below. The subagent loads the methodology via `skill_view("amphi-loop:amphibious-<phase>")` as its first action. Subagents on Hermes cannot call `clarify`, `delegate_task`, `memory`, `send_message`, or `execute_code`. Same fall-through rule — return early with a question if clarification is needed.

---

## Phase 1: Initialize Task

Generate a `TASK.md` template file in `{PROJECT_ROOT}` for the user to describe their task. Read the template from `{PLUGIN_ROOT}/templates/build-task-template.md` and write its contents verbatim to `{PROJECT_ROOT}/TASK.md`. The template includes sections for *Task Description*, *Expected Output*, *Domain References*, and *Notes*. After writing the file, tell the user: A task template has been created at `TASK.md`. Please fill it in.

Wait for the user to confirm. Then read `{PROJECT_ROOT}/TASK.md` and understand:

- **Task Description** — goal of the project.
- **Expected Output** — what indicates success.
- **Domain References** — list of paths to domain reference files (may be empty). Each entry may be a SKILL.md, CLI help dump, SDK doc, style guide, or any other material that teaches the agents *how to act* or *what rules to follow*. Resolve each path (relative paths resolve against `{PROJECT_ROOT}`) and confirm it exists. Any missing path is a validation error — ask the user (open-ended) to correct it before proceeding.
- **Notes** — optional additional constraints.

If Task Description or Expected Output is empty, ask the user (open-ended) to complete it before proceeding.

### Domain auto-detection (only if `SELECTED_DOMAIN` is unresolved)

1. List the subdirectories under `{PLUGIN_ROOT}/domain-context/`. Each subdirectory is a candidate domain.
2. For each candidate, read its `intent.md` (the matching criteria for that domain).
3. Compare the Task Description + Expected Output + Notes against each domain's `intent.md`. Pick the **single best match**, or `none` if no domain has strong signals.
4. If a candidate matches, present the decision to the user with:

   - **question**: `Detected domain: <domain>. Use the pre-distilled <domain> context for exploration, code generation, and verification?`
   - **choices**: `["Yes — use <domain> context", "No — use the generic flow", "Other — let me name a different domain"]`

   On **Yes** set `SELECTED_DOMAIN = <domain>`. On **No** leave unresolved (generic flow). On **Other** ask (open-ended) which domain (must match an existing subdirectory) and set accordingly.

5. If no candidate matches, do not ask — silently proceed with the generic flow (`SELECTED_DOMAIN` stays unresolved).

After this step `SELECTED_DOMAIN` is either a valid domain name or unresolved (generic).

---

## Phase 2: Configure & Setup

**Execute yourself**, in this thread, by loading the `amphibious-config` methodology document and following its steps in order with the inputs already established in Phase 1 (`PLUGIN_ROOT`, `PROJECT_ROOT`, `SELECTED_DOMAIN`, the parsed TASK.md fields).

How to load the methodology:

- **On Claude Code** — open and read `{PLUGIN_ROOT}/agents/amphibious-config.md`.
- **On Hermes** — call `skill_view("amphi-loop:amphibious-config")`.

> **Do NOT delegate Phase 2 to a subagent.** The methodology requires user interaction (project mode, LLM config, domain config). Subagents on either host are restricted from those tools — running Phase 2 in a child would deadlock.

The methodology document covers, in this order:

1. Project Mode (Workflow | Amphiflow) — interactive
2. LLM Configuration (`{PLUGIN_ROOT}/scripts/run/check-dotenv.sh`)
3. Domain-specific Configuration (`{PLUGIN_ROOT}/domain-context/<domain>/config.md`, if any)
4. Environment Setup (`{PLUGIN_ROOT}/scripts/run/setup-env.sh "{PROJECT_ROOT}"` — verifies the `uv` toolchain and runs `uv init --bare` in `PROJECT_ROOT`)
5. Write `{PROJECT_ROOT}/.bridgic/build_context.md` (the single source of truth for Phases 3–5)

If `setup-env.sh` exits non-zero, the methodology says to **stop the entire pipeline** — respect that and do not enter Phase 3.

On successful completion, `{PROJECT_ROOT}/.bridgic/build_context.md` exists and is the only artifact later phases need to read for context.

---

## Phase 3: Exploration (subagent)

Dispatch a subagent that runs the `amphibious-explore` methodology. Per the Agent invocation contract, pass exactly the two paths defined there.

**On Claude Code** — delegate to the `amphibious-explore` subagent (Task tool, `subagent_type: "amphibious-explore"`). The prompt should restate the goal, the two paths, and the return contract from the Hermes block below — every line still applies.

**On Hermes** — invoke `delegate_task` once with:

- **goal**: `Run the amphi-loop:amphibious-explore skill against the task in build_context.md and produce ${PROJECT_ROOT}/.bridgic/explore/exploration_report.md plus any artifact files. Exit only when the report's self-check is satisfied per the skill's exit criteria.`
- **toolsets**: `["terminal", "file", "skills", "web"]` (the subagent needs `skills` to call `skill_view`, `web` for any reference lookups)
- **context** (multi-line — must be self-contained because subagents have NO memory of this conversation):
  ```
  STEP 1: Load the skill content via skill_view("amphi-loop:amphibious-explore"). Follow its instructions exactly.

  Per the skill's "## Input" section, you receive exactly two paths:
  - build_context_path: {PROJECT_ROOT}/.bridgic/build_context.md
  - domain_context_path: {PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/explore.md   # OR the literal string `none` if generic

  All other inputs (TASK.md, references, env state) are discoverable from build_context.md.

  Constraints:
  - You CANNOT call clarify, delegate_task, memory, send_message, or execute_code (subagent restrictions). If a clarification is genuinely needed, return early with a precise question for the parent to ask the user.

  Return: a one-paragraph summary of what was explored, the absolute path of exploration_report.md, and the list of artifact files written under ${PROJECT_ROOT}/.bridgic/explore/.
  ```

When the subagent returns, **refresh `build_context.md`** per the Agent invocation contract: replace `## Outputs → exploration_report` with the returned absolute path, and refresh `env_ready` from the current `{PROJECT_ROOT}/pyproject.toml`. Then proceed to Phase 4.

---

## Phase 4: Generate Amphibious Code (subagent)

Dispatch a subagent that runs the `amphibious-code` methodology. Per the Agent invocation contract, pass exactly the two paths defined there.

**On Claude Code** — delegate to the `amphibious-code` subagent (Task tool, `subagent_type: "amphibious-code"`). The prompt should restate the goal, the two paths, and the return contract from the Hermes block below.

**On Hermes** — invoke `delegate_task` with:

- **goal**: `Run the amphi-loop:amphibious-code skill to generate the bridgic-amphibious project under ${PROJECT_ROOT}/<project-name>/ from the exploration report referenced in build_context.md. Exit when agents.py / tools.py / helpers.py / main.py / config.py are written and pass python -m py_compile.`
- **toolsets**: `["terminal", "file", "skills"]`
- **context**:
  ```
  STEP 1: Load the skill content via skill_view("amphi-loop:amphibious-code"). Follow its instructions exactly.

  Per the skill's input contract, you receive exactly two paths:
  - build_context_path: {PROJECT_ROOT}/.bridgic/build_context.md
  - domain_context_path: {PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/code.md   # OR the literal string `none`

  Read build_context.md to discover: task brief, mode (workflow|amphiflow), llm_configured, references, exploration_report path. The skill's mode/LLM mapping rules tell you how to translate these into agent.arun() arguments and OpenAILlm initialization.

  Constraints:
  - You CANNOT call clarify, delegate_task, memory, send_message, or execute_code.
  - Write all generated files under ${PROJECT_ROOT}/<project-name>/ (the project name is yours to choose; record it in your return summary).

  Return: a one-paragraph summary of what was generated, the absolute path of the generator_project directory, and the list of files written.
  ```

When the subagent returns, **refresh `build_context.md`**: replace `## Outputs → generator_project` with the returned absolute path, and refresh `env_ready` from the current `{PROJECT_ROOT}/pyproject.toml` (Phase 4 may have `uv add`-ed dependencies). Then proceed to Phase 5.

---

## Phase 5: Verify (subagent)

Dispatch a subagent that runs the `amphibious-verify` methodology. Per the Agent invocation contract, pass exactly the two paths defined there.

**On Claude Code** — delegate to the `amphibious-verify` subagent (Task tool, `subagent_type: "amphibious-verify"`). The prompt should restate the goal, the two paths, and the return contract from the Hermes block below.

**On Hermes** — invoke `delegate_task` with:

- **goal**: `Run the amphi-loop:amphibious-verify skill against the generator_project under ${PROJECT_ROOT}/<project-name>/ until it returns Status=PASS or hits one of its repair caps. Return the Status and (on FAIL) the failure_class.`
- **toolsets**: `["terminal", "file", "skills"]`
- **context**:
  ```
  STEP 1: Load the skill content via skill_view("amphi-loop:amphibious-verify"). Follow its instructions exactly.

  Per the skill's input contract, you receive exactly two paths:
  - build_context_path: {PROJECT_ROOT}/.bridgic/build_context.md
  - domain_context_path: {PLUGIN_ROOT}/domain-context/<SELECTED_DOMAIN>/verify.md   # OR the literal string `none`

  Read build_context.md to discover: task brief, mode, generator_project path, exploration_report path, references.

  Artifact-root contract (CRITICAL):
  - Every monitor.sh invocation MUST be launched with BRIDGIC_ARTIFACT_ROOT=${PROJECT_ROOT} so verify artifacts (run.log, pid, failures.log, human-input signal files) land under ${PROJECT_ROOT}/.bridgic/verify/, the same tree explore wrote to. Splitting .bridgic/ between root and inner project is the single source of truth bug we keep hitting — never call monitor.sh without this env var.

  Constraints:
  - You CANNOT call clarify, delegate_task, memory, send_message, or execute_code. If you encounter a `failure_class` of `semantic_drift` or `exploration_gap`, do NOT ask the user — return the diagnosis to the parent for routing.

  Return: Status (PASS/FAIL), failure_class (if FAIL), and a one-paragraph diagnosis citing the relevant lines from ${PROJECT_ROOT}/.bridgic/verify/failures.log when applicable.
  ```

### Routing on Phase 5 outcome

The subagent returns a Status (`PASS` / `FAIL`) and, on `FAIL`, a `failure_class`. Route as follows — **do not re-invoke the verify subagent** when the class explicitly hands work back to an earlier phase:

| `failure_class` | What to do |
|---|---|
| _(none — Status=PASS)_ | Pipeline complete. Report success to the user with a summary of artifacts produced under `{PROJECT_ROOT}` (TASK.md, build_context.md, exploration_report.md, generator_project/, verify run logs). |
| `env_error` | The verify subagent exhausted its env_error cap. The environment cannot be configured automatically — surface the underlying signal (missing env key / dep / endpoint) and the `failures.log` excerpt to the user via plain output, and stop. The user must fix the environment manually before another build run. |
| `code_bug` (after the in-verify repair cap) | The verify subagent exhausted its repair cap; the same defect class survived multiple patch attempts. **Do NOT re-enter Phase 4** — Phase 4 regenerates from the same `exploration_report.md` and would almost certainly produce the same defect. Surface the `failures.log` excerpt + the relevant code lines to the user with a brief diagnosis and stop. The user must either correct the exploration manually, amend `TASK.md`, or accept the failure. |
| `exploration_gap` | **Re-invoke Phase 3** with an explicit augmentation in the goal: "the previous exploration missed _<state/branch cited in `failures.log`>_; record it in Operation Sequence and Self-Check, then regenerate." After Phase 3 produces the updated report, refresh build_context.md, then re-invoke Phase 5. |
| `semantic_drift` | The interpretation of the task in build_context.md does not match the actual produced output. Present the verify diagnosis to the user with choices `["Amend TASK.md (regenerate build_context.md and re-run from Phase 3)", "Accept the produced output (mark complete)"]`. On Amend, edit TASK.md, re-enter Phase 1 to re-derive build_context.md, then continue. On Accept, report success and stop. Do not silently rewrite code. |

A single Phase 5 invocation can route at most **once** per pipeline run to each of `exploration_gap` and `semantic_drift` — if a second of the same class arises, stop and ask the user (the failure class is persistent, indicating a deeper problem with the task/exploration that automation should not paper over).
