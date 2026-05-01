---
name: amphiloop-build
description: Drive AmphiLoop's 5-phase pipeline inside OpenClaw. Host orchestrates and verifies; the built-in `coding-agent` skill writes all code. Host and coding-agent communicate via shared files in the working directory (`.amphiloop/AGENT_BRIEF.md` + `.amphiloop/TODOS.md`), not by stuffing big prompts. ONE long-lived worker session for the whole run, sequential. Worker (claude/codex/opencode/pi) is chosen by the user at run start.
user-invocable: true
metadata:
  openclaw:
    emoji: 🌊
    requires:
      anyBins: ["claude", "codex", "opencode", "pi"]
      config: ["skills.entries.coding-agent.enabled"]
---

# AmphiLoop Build (OpenClaw)

Turn a task description into a runnable bridgic-amphibious Python project.

## Architecture

- **Host (you)** — the brain: reasoning, planning, verifying. You prepare a working directory with `.amphiloop/AGENT_BRIEF.md` (what the worker must read) + `.amphiloop/TODOS.md` (what the worker must do). When verify finds bugs, you append them as new TODO entries.
- **`coding-agent` skill** — the hands: a worker (`claude`/`codex`/`opencode`/`pi`) reads the brief, reads the bridgic-* SKILL.md files it points to so the API is correct, then works through TODOS.md ticking items off as it goes.

**Communication channel** is the working directory, not the prompt. The kickoff prompt stays short (~200 chars: "read AGENT_BRIEF.md, read TODOS.md, work through them"). Methodology, API references, and bug reports all flow through files. This avoids context overflow, lets the host monitor progress by re-reading TODOS.md, and forces the worker to actually read the bridgic skill SKILL.md files.

**Single long-lived worker session** for the whole run (strictly sequential) so the worker carries context from initial generation into any follow-up fix.

## Argument parsing

`/amphiloop_build [--<domain>]`

- **`--<domain>` present** (e.g. `--browser`) → set `SELECTED_DOMAIN = <domain>` and skip Phase 1 auto-detection. Validate that `{baseDir}/../../domain-context/<domain>/` exists. If it does not, list available domains and ask the user to pick one or rerun without a flag.
- **No flag** → leave `SELECTED_DOMAIN` unresolved; resolve it during Phase 1's auto-detection step.
- **Anything else** (extra tokens, multiple flags, free-form text) → stop and ask the user to clarify. Do not silently treat free-form text as TASK.md content — Phase 1 owns TASK.md construction.

## Pipeline overview

```
A0. Parse arguments              ── argument handling (see above)
A.  Pick coding worker            ── user picks claude / codex / opencode / pi
B.  Prepare working directory     ── confirm <projectRoot>, capture notification route
B'. Initialize Task  (Phase 1)   ── seed TASK.md template, user fills in, validate, domain auto-detect
C.  Configure & Setup (Phase 2)  ── project mode, LLM config, env setup → build_context.md
D.  Explore           (Phase 3)  ── probe target environment → .bridgic/explore/exploration_report.md
E0. Prepare work template         ── write AGENT_BRIEF.md + TODOS.md
E.  Generate Code     (Phase 4)  ── open coding-agent session, worker completes TODOs
F.  Verify            (Phase 5)  ── run monitor.sh, fix-attempt loop via TODOS.md
G.  Cleanup & report              ── kill session, send summary
```

> **Path variables** — used throughout this document:
>
> | Variable | Resolves to |
> |---|---|
> | `{baseDir}` | Directory containing this SKILL.md |
> | `{baseDir}/../..` | AmphiLoop repository root (agents, skills, templates, scripts, domain-context) |
> | `<projectRoot>` | User-confirmed working directory for the generated project (set in Step B) |
> | `build_context_path` | `<projectRoot>/.bridgic/build_context.md` |
> | `domain_context_path` | `{baseDir}/../../domain-context/<SELECTED_DOMAIN>/<phase>.md` when resolved; `none` otherwise |
>
> `build_context.md` is the single source of truth for Phase 3→5 — every later step reads it for context, and Phase 3 / Phase 4 each fill their `## Outputs` placeholder after completing.

This skill reads methodology files from `{baseDir}/../../agents/`, the task template from `{baseDir}/../../templates/build-task-template.md`, domain-context from `{baseDir}/../../domain-context/<domain>/`, and helper scripts from `{baseDir}/../../scripts/run/` — **do not ask the user for an AmphiLoop path**.

## Human interaction & step checkpoints

Every prompt to the user — including the gates between steps and in-step side-effect gates — MUST follow `{baseDir}/../../agents/human-interaction-protocol.md`. Read it once before starting Step A0. The host operates at **Tier 2**: every gate is a clearly formatted chat message that waits for the user's explicit textual reply.

**Mandatory step-transition gates** (send a 1–3 line summary + "Continue?" question; wait for `yes` / `y` / `continue` before advancing):

| Boundary | Why gate here |
|---|---|
| Step B' → Step C | Phase 1 finished — TASK.md validated, `SELECTED_DOMAIN` resolved. About to enter Phase 2 which collects pipeline mode, LLM credentials, and runs `setup-env.sh`. |
| Step C → Step D | Config decisions recorded. About to probe the target environment (may open browsers, hit external sites, mutate user data). |
| Step D → Step E0 | Exploration finished. About to spawn the long-lived worker session and burn LLM tokens for code generation. |
| Step E → Step F | Code frozen. About to run the generated program for the first time under `monitor.sh` (real side effects, real API calls). |
| Each fix attempt in Step F | Before appending FIX-N and re-engaging the worker, give the user a chance to inspect the failure or stop. |

**Mandatory in-step gates**:

- Step C → before `setup-env.sh` runs (surfaced by `amphibious-config.md` Step 4.0).
- Step D → any `HUMAN:` handoff during exploration (login wall, CAPTCHA, etc.) — ask via chat; never echo + poll.
- Step F → on `monitor.sh` exit code 2 — relay the runtime prompt to the user per the verify methodology's OpenClaw addendum.

The user must always have the option to interrupt and redirect at every gate. Silence is **not** consent.

---

### Step A0. Parse arguments

See [Argument parsing](#argument-parsing) above. After this step, `SELECTED_DOMAIN` is either a valid domain name or unresolved.

### Step A. Pick the coding worker

Send the user exactly:

> About to start AmphiLoop build. Pick the coding worker for this run:
> `claude` (recommended) | `codex` | `opencode` | `pi` (not recommended).
> Reply with one word.

Wait for the reply. Record it as `<worker>`. Reuse `<worker>` for the entire build run; do not switch mid-run.

If the user replies with anything other than the four valid options, ask again rather than guessing.

### Step B. Prepare the working directory

1. Confirm `<projectRoot>` with the user; offer a sensible default (e.g., a fresh `mktemp -d`) if they have not specified one. The AmphiLoop repo path does **not** need to be asked — it is `{baseDir}/../..` by construction.
2. Capture the OpenClaw notification route of the current conversation: `notifyChannel`, `notifyTarget`, `notifyAccount`, `notifyReplyTo`, `notifyThreadId`. You will need them later for Step G.

This step does not write code and does not write `TASK.md`. Do it directly.

---

### Step B'. Phase 1 — Initialize Task

1. **Seed the template.** `read` `{baseDir}/../../templates/build-task-template.md`, then `write` its contents **verbatim** to `<projectRoot>/TASK.md`. Do not modify, summarize, or pre-fill any section.

2. **Tell the user to fill it in.** Send a chat message:

   > A task template has been created at `<projectRoot>/TASK.md`. Please open it, fill in the four sections (`Task Description` / `Expected Output` / `Domain References` / `Notes`), save, and reply `done` to continue (or `cancel` to abort).

3. **Wait for an explicit `done` reply.** Silence is **not** consent. Do not poll a flag file; do not auto-advance after a fixed wait. Any other reply (counter-question, "wait", silence) is handled before re-prompting.

4. **Read TASK.md back** and parse the four sections:
   - **Task Description** — goal of the project.
   - **Expected Output** — what indicates success.
   - **Domain References** — list of paths to domain reference files (may be empty). Each entry may be a SKILL.md, CLI help dump, SDK doc, style guide, or any other material that teaches the agents *how to act* or *what rules to follow*.
   - **Notes** — optional additional constraints.

5. **Validate.**
   - `Task Description` must be non-empty.
   - `Expected Output` must be non-empty.
   - For every `Domain References` entry that is not a comment / example / blank line: resolve relative paths against `<projectRoot>`, use absolute paths as-is, and confirm the file exists on disk. **Any missing path is a hard validation error.**
   - On any failure: send a chat message naming the specific field / path that failed, ask the user to fix `TASK.md` and reply `done` again. Loop until validation passes (or the user replies `cancel`).

6. **Domain auto-detection** — execute **only** if `SELECTED_DOMAIN` is still unresolved after Step A0:
   1. List subdirectories under `{baseDir}/../../domain-context/`. Each subdirectory is a candidate domain.
   2. For each candidate, `read` its `intent.md` (the matching criteria for that domain).
   3. Compare `Task Description + Expected Output + Notes` against each candidate's `intent.md`. Pick the **single best match**, or `none` if no candidate has strong signals.
   4. **If a candidate matches**, present the decision:

      > Detected domain: **`<domain>`**. Use the pre-distilled `<domain>` context for exploration, code generation, and verification?
      >
      > Reply `1` / `yes` — use `<domain>` context.
      > Reply `2` / `no` — proceed with the generic (domain-agnostic) flow.
      > Reply `3 <other-domain>` — specify a different domain explicitly.

      On `1` set `SELECTED_DOMAIN = <domain>`. On `2` leave unresolved (generic flow). On `3 <other>` validate that `{baseDir}/../../domain-context/<other>/` exists and set `SELECTED_DOMAIN = <other>`; otherwise re-prompt.
   5. **If no candidate matches**, do not ask — silently proceed with the generic flow (`SELECTED_DOMAIN` stays unresolved).

   After this step `SELECTED_DOMAIN` is either a valid domain name or unresolved (generic).

7. **Step B' → Step C gate**: summarize in 1–3 lines what just landed (`TASK.md` validated, `SELECTED_DOMAIN = <domain | generic>`, count of resolved Domain References) and ask:

   > Proceed to Phase 2 (Configure & Setup)? This phase will collect pipeline mode and LLM configuration, then run `setup-env.sh` (which modifies the uv toolchain and writes `pyproject.toml`). Reply `yes` to continue, or describe what you want adjusted first.

   Wait for the explicit affirmative before continuing.

This step does not write code; do it directly.

---

### Step C. Phase 2 — Configure & Setup

Inputs from Step B' (already established): parsed `TASK.md` fields (`Task Description`, `Expected Output`, `Domain References` with resolved absolute paths, `Notes`) and `SELECTED_DOMAIN` (a valid domain name or unresolved/generic). **Step C does not re-decide the domain** — that is Phase 1's responsibility.

1. `read` the file `{baseDir}/../../agents/amphibious-config.md` to load the Phase 2 methodology.
2. Following that methodology — and feeding it the pre-resolved inputs above — drive Project Mode selection (Workflow / Amphiflow), LLM Configuration (`check-dotenv.sh`), Domain-specific Configuration (only when `SELECTED_DOMAIN` is resolved and `{baseDir}/../../domain-context/<SELECTED_DOMAIN>/config.md` exists), and Environment Setup (`setup-env.sh`); then `write` the consolidated decision record to `<projectRoot>/.bridgic/build_context.md`. Present every question from the methodology as a clearly formatted chat message and wait for the user's explicit textual reply.

This produces a markdown decision record, not code. Do it directly.

If `setup-env.sh` exits non-zero, the methodology doc says to **stop the entire pipeline** — respect that and do not enter Step D.

On successful completion, `<projectRoot>/.bridgic/build_context.md` exists and is the only artifact later steps need to read for context.

**Step C → D gate**: summarize the recorded decisions (mode, llm_configured, domain) in 1–3 lines and ask: "Proceed to Phase 3 (Explore)? This phase will probe the target environment described in TASK.md — depending on the task it may open browsers, hit external sites, or read local files. Reply `yes` to continue, or describe what you want changed first."

---

### Step D. Phase 3 — Explore

1. `read` the file `{baseDir}/../../agents/amphibious-explore.md` to load the Phase 3 methodology.
2. Following that methodology, use `bash` to observe the target environment (running existing tools, taking notes, capturing samples). `write` the consolidated observations to `<projectRoot>/.bridgic/explore/exploration_report.md`.

Do not start Phase 4 until exploration is complete — the report and artifact files under `<projectRoot>/.bridgic/explore/` are the sole bridge between Phase 3 and Phase 4. After exploration finishes, fill `## Outputs → exploration_report` in `build_context.md`.

Writing notes is not coding — do it directly.

**HUMAN handoff during exploration** (login wall, CAPTCHA, manual confirmation, providing a token, etc.): the methodology already enumerates the tiers and anti-patterns; in this context the **Tier 2 case** applies — use the chat channel captured in Step B.

**Exception**: if the exploration genuinely needs a probe script to be authored, treat that as the **first** code-writing action of the run and jump to Step E0/E (use the probe-script as the first TODO).

**Step D → E0 gate**: summarize what exploration found — operation sequence sketch, any HUMAN steps in the plan, artifacts captured. Ask: "Exploration complete (`<projectRoot>/.bridgic/explore/exploration_report.md`). Proceed to Phase 4 (Code Generation)? This will spawn a long-lived `<worker>` session and burn LLM tokens to write the project. Reply `yes` to continue, or describe what you want adjusted in the plan first."

---

### Step E0. Prepare the work template

Before opening any worker session, host must write two communication files into `<projectRoot>/.amphiloop/`. These are the entire interface between host and worker for this run.

1. **Write `<projectRoot>/.amphiloop/AGENT_BRIEF.md`** — a static reference brief. Use the `write` tool. Recommended structure:

   ```markdown
   # Worker brief

   You are doing the coding for an AmphiLoop bridgic-amphibious project build.
   Working directory: <projectRoot>

   ## STEP 1 — read the bridgic API surface FIRST (mandatory before any code)

   Use your file-read tool on each of these files in order. Do not skip any.

   - {baseDir}/../../skills/bridgic-amphibious/SKILL.md
   - {baseDir}/../../skills/bridgic-llms/SKILL.md
   - {baseDir}/../../skills/bridgic-browser/SKILL.md     ← only if the task involves browser automation; skip otherwise
   - {baseDir}/../../agents/amphibious-code.md           ← the coding methodology you must follow
   - {baseDir}/../../domain-context/<domain>/code.md      ← only if a matching domain context exists

   The bridgic-* SKILL.md files define the actual class names, method signatures, and APIs you must use. Inventing API surface that is not in those files will fail.

   ## STEP 2 — read this run's context

   - <projectRoot>/TASK.md
   - <projectRoot>/.bridgic/build_context.md
   - <projectRoot>/.bridgic/explore/exploration_report.md

   ## STEP 3 — work through TODOS.md

   Open <projectRoot>/.amphiloop/TODOS.md. Pick the topmost open `[ ]` item, complete it, then EDIT TODOS.md in place to change its `[ ]` to `[x]`. Save. Move to the next open item. Repeat until no open items remain.

   ## STEP 4 — when all TODOs are done

   Print exactly this line on stdout and then wait for further input. DO NOT exit:
   `### AMPHI-TASK-DONE ###`

   The orchestrator may append new `[ ]` items to TODOS.md later (e.g. fixes after verification). When you receive a "continue" instruction, re-open TODOS.md, find the new open items, and resume from STEP 3.

   ## Output layout — MANDATORY

   Final deliverable lives **inside** `<projectRoot>/<project-name>/`. amphi.py / main.py / log/ / result/ and every support module MUST be inside `<project-name>/`. Dropping them at `<projectRoot>/` directly is a hard error — the orchestrator will reject the run.

   `<projectRoot>/<project-name>/` layout:
     amphi.py            ← entry, scaffold-created here
     main.py             ← entry, you write here
     log/                ← runtime logs
     result/             ← task outputs
     <support>.py        ← any extra helpers go here too, never at <projectRoot>

   `<projectRoot>/` only carries uv metadata (`pyproject.toml`, `uv.lock`, `.venv/`, `.env`), the AmphiLoop workspace (`.bridgic/`, `.amphiloop/`), and `TASK.md`. Never write code into `<projectRoot>/.bridgic/` — that is the orchestrator's workspace.

   Anti-patterns to avoid:
   - ❌ `amphi.py` / `main.py` at `<projectRoot>/` (sibling of `pyproject.toml`)
   - ❌ Treating `<project-name>/` as a Python import package (adding `__init__.py`, importing it from a sibling main.py at `<projectRoot>/`)
   - ❌ `log/` or `result/` at `<projectRoot>/` instead of inside `<project-name>/`
   - ❌ Any `.py` file written under `<projectRoot>/.bridgic/`
   ```

   When writing this file, substitute real absolute paths for `{baseDir}/../..` and `<projectRoot>`. For the `domain-context/<domain>/code.md` line: if `SELECTED_DOMAIN` is unresolved (the generic flow), **delete that line entirely**; otherwise replace `<domain>` with the resolved domain name (and confirm the file exists — drop the line if it does not). Same drop-if-missing rule applies to the optional `bridgic-browser` line.

2. **Write `<projectRoot>/.amphiloop/TODOS.md`** — the initial Phase 4 task list. Use the `write` tool. Derive 5–8 items by mapping the sections of `{baseDir}/../../agents/amphibious-code.md` into checkboxes. Tailor wording to the current task. A typical seed:

   ```markdown
   # AmphiLoop build TODOs

   - [ ] T1: Scaffold inside `<project-name>/`. Run `mkdir -p <projectRoot>/<project-name> && cd <projectRoot>/<project-name> && uv run bridgic-amphibious create --task "<one-line task>"`. The `cd` is REQUIRED — running the CLI from `<projectRoot>` drops `amphi.py` at the wrong level. After it returns, verify `<projectRoot>/<project-name>/amphi.py` exists; if it landed at `<projectRoot>/amphi.py` instead, move it inside `<project-name>/` and fix.
   - [ ] T2: Create empty `<projectRoot>/<project-name>/log/` and `<projectRoot>/<project-name>/result/` dirs (NOT at `<projectRoot>/log/` or `<projectRoot>/result/`).
   - [ ] T3: In `<project-name>/amphi.py`, define the CognitiveContext for this task following build_context.md.
   - [ ] T4: In `<project-name>/amphi.py`, implement on_workflow yielding ActionCalls that mirror the Operation Sequence in exploration_report.md.
   - [ ] T5: In `<project-name>/amphi.py`, implement on_agent think_units for AMPHIFLOW fallback per the methodology.
   - [ ] T6: Register task tools (FunctionToolSpec) for any domain-specific operations the workflow needs. Inline in `<project-name>/amphi.py` (or split into `<project-name>/tools.py` per the methodology — never at `<projectRoot>/`).
   - [ ] T7: Implement helper functions for parsing VOLATILE refs from ctx.observation. Same placement rule — inside `<project-name>/`.
   - [ ] T8: Write `<project-name>/main.py` with LLM init (per skills/bridgic-llms/SKILL.md), tools assembly, and the agent.arun(...) call.
   - [ ] T9: Run `cd <projectRoot> && uv run python <project-name>/main.py` once dry to confirm it boots without import or syntax errors.
   - [ ] T10: Final layout check — `ls <projectRoot>` should show `pyproject.toml`, `uv.lock`, `.venv/`, `.env`, `.bridgic/`, `.amphiloop/`, `TASK.md`, `<project-name>/` and NOTHING ELSE. Any `.py` file at `<projectRoot>/` is a violation.
   ```

3. Send a short progress note to the user: "Worker brief and TODO list written to `<projectRoot>/.amphiloop/`. Opening coding-agent session next."

---

### Step E. Phase 4 — Generate Code

This is the first code-writing action of the run (unless Step D opened the session for a probe). The goal: open one worker session, capture `<workerSession>`, and submit a tiny pointer prompt that hands the worker over to AGENT_BRIEF.md + TODOS.md.

1. **Invoke the `coding-agent` skill.** Tell it:
   - `Worker: <worker>`
   - `Workdir: <projectRoot>` (so the worker starts in the right place; `cd` into it via the spawn config)
   - `Mode: INTERACTIVE` — launch the worker in REPL/interactive mode, **not** a one-shot. Concretely: `claude` must be launched **without** `--print`; `codex` **without** `exec`; `pi` and `opencode` in their REPL form. PTY rules and exact spawn flags are coding-agent's responsibility — do not hand-roll bash here.
   - `Background: yes` (coding-agent's hard rule).
   - `This is a long-lived orchestrated session.` Tell coding-agent: do **not** require the worker to self-notify the user via `openclaw message send` per task. The orchestrator (this skill) will summarize at Step G.
   - `Capture the OpenClaw process sessionId returned by bash background:true and report it back so the orchestrator can remember it as <workerSession>.`

2. Once you have `<workerSession>`, submit the **kickoff prompt** via `process action:submit sessionId:<workerSession> data:<prompt>`. The prompt is short and is the SAME shape every time:

   > Working directory is `<projectRoot>`. First, read `.amphiloop/AGENT_BRIEF.md` end-to-end and follow it (it tells you which SKILL.md files to read so you know the bridgic API surface, and which context files to read for this task). Then read `.amphiloop/TODOS.md` and work through every open `[ ]` item top-to-bottom, editing TODOS.md to change `[ ]` to `[x]` as you finish each one. When all items are `[x]`, print exactly `### AMPHI-TASK-DONE ###` on its own line and wait for further input. DO NOT exit or terminate.

   Do NOT paste methodology, build_context, or exploration data into the prompt — they are reachable from AGENT_BRIEF.md.

3. Send a short progress note to the user before submitting ("Phase 4: handing TODOs to the worker — read TODOS.md to follow along").

4. Monitor with `process action:log sessionId:<workerSession>` until the sentinel `### AMPHI-TASK-DONE ###` appears. Optionally `read` `<projectRoot>/.amphiloop/TODOS.md` periodically to watch `[x]` count rise.

5. **Do NOT kill the session.**

6. After the worker completes (sentinel appears and all TODOS are `[x]`), fill `## Outputs → generator_project` in `build_context.md` with the path to `<projectRoot>/<project-name>/`.

7. **Step E → F gate**: summarize the worker's output — list the files now under `<projectRoot>/<project-name>/` (`amphi.py`, `main.py`, etc.), confirm `[x]` count on TODOS.md. Ask: "Code generation complete. Proceed to Phase 5 (Verify)? This will run the generated program for the first time under `monitor.sh` — it will execute against the real target environment, may make real API calls, and may surface runtime `HumanCall` prompts you'll need to answer. Reply `yes` to continue, or `pause` to inspect the generated code first." Wait for the explicit affirmative reply.

---

### Step F. Phase 5 — Verify

1. `read` the file `{baseDir}/../../agents/amphibious-verify.md` to load the Phase 5 methodology.
2. Run `{baseDir}/../../scripts/run/monitor.sh` against the generated project via `bash` (or follow whatever execution recipe the methodology prescribes for this run). Collect the output.

   **If `monitor.sh` exits with code 2** (the running program hit a `HumanCall`), follow the verify methodology's **OpenClaw addendum** — host reads `<projectRoot>/.bridgic/verify/human_request.json`, relays the prompt to the user via chat, writes the user's reply into `human_response.json`, and re-invokes `monitor.sh`. **Never** invent a polling loop here; the protocol forbids it.

3. Decide based on the exit:
   - **Pass** — proceed to Step G.
   - **Fail, root cause is in the generated code** (logic error, missing import, wrong API call, etc.) — apply a **fix-attempt gate** before re-engaging the worker:
     - Send the user: `[CHECKPOINT]` Phase 5 verify failed (attempt N/3). One-line root cause: `<root cause>`. Proposed fix: `<expected fix>`. Reply `yes` to append FIX-N to TODOS.md and ask the worker to retry; reply `stop` to abort and inspect manually; or reply with edits to the proposed fix wording.
     - Wait for the user's explicit reply.
     - On `yes` (or an edited fix description): **append** one or more FIX entries to `<projectRoot>/.amphiloop/TODOS.md` (use `read` then `write` the full new content; the worker is sentinel-waiting and not touching the file right now). Format each entry as:
       ```markdown
       - [ ] FIX-N: <relative-path>:<line> — <one-line root cause> — <expected fix>
         <optional 1–3 lines of relevant verify-log excerpt>
       ```
       Use a stable monotonic N across attempts (FIX-1, FIX-2, ...).
     - Submit a one-line continue prompt to the **same** `<workerSession>` via `process action:submit sessionId:<workerSession> data:<prompt>`:
       > New FIX entries appended to `.amphiloop/TODOS.md`. Re-read TODOS.md and resume from the first open `[ ]` item. Same rules as before: tick each item to `[x]` as you finish, then print `### AMPHI-TASK-DONE ###` and wait. DO NOT exit.
     - Monitor with `process action:log` until the sentinel reappears.
     - Re-run verification (return to Step F.2).
     - On `stop` → proceed to Step G with `fail` status and the user-aborted reason.
   - **Fail, root cause is NOT code** (missing env var, missing credential, network issue, missing input data):
     - Send the user: `[USER ACTION REQUIRED]` Phase 5 failed for a non-code reason: `<exact missing/broken thing>`. Reply with the missing value (e.g. an env var assignment), or `cancel` to stop the run.
     - Apply the user's instructions yourself with `bash` / `write` (do not append a FIX TODO and do not submit to the worker).
     - Re-run verification.

4. Cap fix attempts at 3. After 3 consecutive code-fix attempts that still fail, stop the loop and proceed to Step G with a `fail` status.

---

### Step G. Cleanup and report

1. Kill the long-lived worker session: `process action:kill sessionId:<workerSession>`.
2. Send a final summary to the user with `openclaw message send` (use the notification route captured in Step B). Include:
   - Pass / fail status
   - Path to the generated project (`<projectRoot>/<project-name>/`)
   - Number of coding-agent turns used (1 for the Phase 4 prompt, plus N for fix attempts)
   - If `fail`: the last failure summary so the user knows what to investigate

---

## Common constraints

- **Never write code yourself.** All code-writing — Phase 4 generation, Phase 5 fixes, Phase 3 probe scripts, anything else — must go through `process:submit` to `<workerSession>` and the TODO list. Do not edit `.py` / `.ts` / `.sh` files with the host's `write` or `edit` tools. (`<projectRoot>/.amphiloop/AGENT_BRIEF.md` and `TODOS.md` are written by the host — those are protocol files, not code.)
- **All worker direction flows through TODOS.md.** Methodology, API references, and bug reports go into `<projectRoot>/.amphiloop/AGENT_BRIEF.md` and `<projectRoot>/.amphiloop/TODOS.md`, not into the prompt. The kickoff prompt and continue prompt are deliberately tiny pointers to those files.
- **One worker, one sessionId, for the whole run.** `<worker>` is chosen once in Step A; `<workerSession>` is opened once in Step E (or earlier in a Step D probe) and reused throughout.
- **Strictly sequential, no concurrent file writes.** The worker handles one prompt at a time. The host writes to TODOS.md only while the worker is sentinel-waiting; the worker writes to TODOS.md only while it is actively working. This is enforced by the sequential prompt/sentinel cycle.
- **Sentinel discipline.** Every prompt you submit ends with the requirement to print `### AMPHI-TASK-DONE ###` so you have a deterministic completion signal. If after a generous wait the sentinel has not appeared but the expected files exist and the worker output has been quiet, treat that as completion (sentinel missed) and proceed.
- **Verify the worker actually read the brief.** After the kickoff prompt, scan `process:log` for evidence the worker called its file-read tool on the bridgic-* SKILL.md files listed in AGENT_BRIEF.md. If it skipped them (jumped straight to coding), inject one corrective `process:submit`: "You skipped the brief. STOP and read `.amphiloop/AGENT_BRIEF.md` STEP 1 files now before any further code."
- **Do not re-implement coding-agent.** Do not write `claude --print '...'` / `codex exec '...'` style bash here — coding-agent's SKILL.md owns spawn details (PTY, background, flags). This skill only tells coding-agent **what** to launch and **how** to drive it via `process:submit`.
- **Progress visibility.** Send a one-line progress note before each `process:submit` so the user can follow the run.
- **Notification deviation.** Tell coding-agent up front this is a long-lived orchestrated session and the orchestrator will summarize at Step G. Do not have the worker self-notify per task.
