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

**Division of labor**:

- **Host (you)** — the brain: reasoning, planning, verifying. You prepare a working directory with `.amphiloop/AGENT_BRIEF.md` (what the worker must read) + `.amphiloop/TODOS.md` (what the worker must do). When verify finds bugs, you append them as new TODO entries.
- **`coding-agent` skill** — the hands: a worker (`claude`/`codex`/`opencode`/`pi`) reads the brief, reads the bridgic-* SKILL.md files it points to so the API is correct, then works through TODOS.md ticking items off as it goes.

**Communication channel** is the working directory, not the prompt. The prompt to the worker stays short (~200 chars: "read AGENT_BRIEF.md, read TODOS.md, work through them"). Methodology, API references, and bug reports all flow through files. This avoids context overflow, lets the host monitor progress by re-reading TODOS.md, and forces the worker to actually read the bridgic skill SKILL.md files instead of hoping its prompt mentioned them.

**Single long-lived worker session** for the whole run (strictly sequential) so the worker carries context from initial generation into any follow-up fix.

## Inputs / Outputs

- **Inputs**:
  - `<taskSpec>`: free-form natural-language task description from the user
  - `<projectRoot>`: working directory the project will live under (ask the user; create it if it does not exist)
- **Output**: `<projectRoot>/<project-name>/{amphi.py, main.py, log/, result/}`

## Path resolution

This skill ships **inside** the AmphiLoop repository at `<repo>/extensions/openclaw-skill/amphiloop-build/`. The OpenClaw `{baseDir}` macro at runtime resolves to the directory containing this SKILL.md, so the AmphiLoop repo root is always `{baseDir}/../..`. The skill reads the methodology files under `{baseDir}/../../agents/` and helper scripts under `{baseDir}/../../scripts/run/` directly via that path — **do not ask the user for an AmphiLoop path**.

## Mandatory flow

Execute the steps in order. Never skip; never re-order. Throughout, **do not write or edit code yourself** — every code-touching action goes through `<workerSession>` (opened in Step E).

### Step A. Pick the coding worker (must ask the user)

Send the user exactly:

> About to start AmphiLoop build. Pick the coding worker for this run:
> `claude` (recommended) | `codex` | `opencode` | `pi` (not recommended).
> Reply with one word.

Wait for the reply. Record it as `<worker>`. Reuse `<worker>` for the entire build run; do not switch mid-run.

If the user replies with anything other than the four valid options, ask again rather than guessing.

### Step B. Prepare the working directory

1. Confirm `<projectRoot>` with the user; offer a sensible default (e.g., a fresh `mktemp -d`) if they have not specified one. The AmphiLoop repo path does **not** need to be asked — it is `{baseDir}/../..` by construction.
2. Use the `write` tool to write `<taskSpec>` verbatim into `<projectRoot>/TASK.md`.
3. Capture the OpenClaw notification route of the current conversation: `notifyChannel`, `notifyTarget`, `notifyAccount`, `notifyReplyTo`, `notifyThreadId`. You will need them later for Step G.

This step does not write code; do it directly.

### Step C. Phase 2 — Config (host runs this directly)

1. `read` the file `{baseDir}/../../agents/amphibious-config.md` to load the Phase 2 methodology.
2. Following that methodology, read `<projectRoot>/TASK.md`, decide pipeline mode and any domain context, and `write` the result to `<projectRoot>/.bridgic/build_context.md`.

This produces a markdown decision record, not code. Do it directly.

### Step D. Phase 3 — Explore (host runs this directly)

1. `read` the file `{baseDir}/../../agents/amphibious-explore.md` to load the Phase 3 methodology.
2. Following that methodology, use `bash` to observe the target environment (running existing tools, taking notes, capturing samples). `write` the consolidated observations to `<projectRoot>/.bridgic/exploration/exploration_report.md`.

Writing notes is not coding — do it directly.

**Exception**: if the exploration genuinely needs a probe script (Python / JS / shell) to be authored to make further observations possible, treat that probe-script authorship as the **first** code-writing action of the run and jump to Step E0/E now (use the probe-script as the first TODO).

### Step E0. Prepare the work template (★ v8 ★ host writes the brief and TODO list before any coding)

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
   - <projectRoot>/.bridgic/exploration/exploration_report.md

   ## STEP 3 — work through TODOS.md

   Open <projectRoot>/.amphiloop/TODOS.md. Pick the topmost open `[ ]` item, complete it, then EDIT TODOS.md in place to change its `[ ]` to `[x]`. Save. Move to the next open item. Repeat until no open items remain.

   ## STEP 4 — when all TODOs are done

   Print exactly this line on stdout and then wait for further input. DO NOT exit:
   `### AMPHI-TASK-DONE ###`

   The orchestrator may append new `[ ]` items to TODOS.md later (e.g. fixes after verification). When you receive a "continue" instruction, re-open TODOS.md, find the new open items, and resume from STEP 3.

   ## Output layout

   Final deliverable goes under `<projectRoot>/<project-name>/`:
     amphi.py
     main.py
     log/
     result/
   ```

   When writing this file, substitute real absolute paths for `{baseDir}/../..` and `<projectRoot>` and `<domain>` (drop lines whose source files don't exist for the current run).

2. **Write `<projectRoot>/.amphiloop/TODOS.md`** — the initial Phase 4 task list. Use the `write` tool. Derive 5–8 items by mapping the Phase 1–4 sections of `{baseDir}/../../agents/amphibious-code.md` into checkboxes. Tailor wording to the current task. A typical seed:

   ```markdown
   # AmphiLoop build TODOs

   - [ ] T1: Scaffold `<project-name>/` via the bridgic-amphibious CLI (per skills/bridgic-amphibious/SKILL.md). Create empty log/ and result/ dirs.
   - [ ] T2: In amphi.py, define the CognitiveContext for this task following build_context.md.
   - [ ] T3: In amphi.py, implement on_workflow yielding ActionCalls that mirror the Operation Sequence in exploration_report.md.
   - [ ] T4: In amphi.py, implement on_agent think_units for AMPHIFLOW fallback per the methodology.
   - [ ] T5: Register task tools (FunctionToolSpec) for any domain-specific operations the workflow needs.
   - [ ] T6: Implement helper functions for parsing VOLATILE refs from ctx.observation.
   - [ ] T7: Write main.py with LLM init (per skills/bridgic-llms/SKILL.md), tools assembly, and the agent.arun(...) call.
   - [ ] T8: Run `uv run main.py` once dry to confirm it boots without import or syntax errors.
   ```

3. Send a short progress note to the user: "Worker brief and TODO list written to `<projectRoot>/.amphiloop/`. Opening coding-agent session next."

### Step E. Phase 4 — Code (★ open the long-lived coding-agent session with a SHORT prompt ★)

This is the first code-writing action of the run (unless Step D opened the session for a probe). The goal: open one worker session, capture `<workerSession>`, and submit a tiny pointer prompt that hands the worker over to AGENT_BRIEF.md + TODOS.md.

1. **Invoke the `coding-agent` skill.** Tell it:
   - `Worker: <worker>`
   - `Workdir: <projectRoot>` (so the worker starts in the right place; `cd` into it via the spawn config)
   - `Mode: INTERACTIVE` — launch the worker in REPL/interactive mode, **not** a one-shot. Concretely: `claude` must be launched **without** `--print`; `codex` **without** `exec`; `pi` and `opencode` in their REPL form. PTY rules and exact spawn flags are coding-agent's responsibility — do not hand-roll bash here.
   - `Background: yes` (coding-agent's hard rule).
   - `This is a long-lived orchestrated session.` Tell coding-agent: do **not** require the worker to self-notify the user via `openclaw message send` per task. The orchestrator (this skill) will summarize at Step G. This deviation from the standard Mandatory Pattern is sanctioned by coding-agent's own contract ("if you do not have a trustworthy notification route, say so and do not claim that completion will notify the user automatically").
   - `Capture the OpenClaw process sessionId returned by bash background:true and report it back so the orchestrator can remember it as <workerSession>.`

2. Once you have `<workerSession>`, submit the **kickoff prompt** via `process action:submit sessionId:<workerSession> data:<prompt>`. The prompt is short and is the SAME shape every time:

   > Working directory is `<projectRoot>`. First, read `.amphiloop/AGENT_BRIEF.md` end-to-end and follow it (it tells you which SKILL.md files to read so you know the bridgic API surface, and which context files to read for this task). Then read `.amphiloop/TODOS.md` and work through every open `[ ]` item top-to-bottom, editing TODOS.md to change `[ ]` to `[x]` as you finish each one. When all items are `[x]`, print exactly `### AMPHI-TASK-DONE ###` on its own line and wait for further input. DO NOT exit or terminate.

   Do NOT paste methodology, build_context, or exploration data into the prompt — they are reachable from AGENT_BRIEF.md.

3. Send a short progress note to the user before submitting ("Phase 4: handing TODOs to the worker — read TODOS.md to follow along").

4. Monitor with `process action:log sessionId:<workerSession>` until the sentinel `### AMPHI-TASK-DONE ###` appears. Optionally `read` `<projectRoot>/.amphiloop/TODOS.md` periodically to watch `[x]` count rise.

5. **Do NOT kill the session.** Continue to Step F.

### Step F. Phase 5 — Verify (host runs verify; bugs flow back via TODOS.md ★)

1. `read` the file `{baseDir}/../../agents/amphibious-verify.md` to load the Phase 5 methodology.
2. Run `{baseDir}/../../scripts/run/monitor.sh` against the generated project via `bash` (or follow whatever execution recipe the methodology prescribes for this run). Collect the output.
3. Decide:
   - **Pass** — proceed to Step G.
   - **Fail, root cause is in the generated code** (logic error, missing import, wrong API call, etc.):
     - Send a short progress note to the user ("Phase 5 verify failed; appending FIX TODOs (attempt N/3) and asking worker to continue").
     - **Append** one or more FIX entries to `<projectRoot>/.amphiloop/TODOS.md` (use `read` then `write` the full new content; the worker is sentinel-waiting and not touching the file right now, so there is no write conflict). Format each entry as:
       ```markdown
       - [ ] FIX-N: <relative-path>:<line> — <one-line root cause> — <expected fix>
         <optional 1–3 lines of relevant verify-log excerpt>
       ```
       Use a stable monotonic N across attempts (FIX-1, FIX-2, ...).
     - Submit a one-line continue prompt to the **same** `<workerSession>` via `process action:submit sessionId:<workerSession> data:<prompt>`. The prompt is literally:
       > New FIX entries appended to `.amphiloop/TODOS.md`. Re-read TODOS.md and resume from the first open `[ ]` item. Same rules as before: tick each item to `[x]` as you finish, then print `### AMPHI-TASK-DONE ###` and wait. DO NOT exit.
     - Monitor with `process action:log` until the sentinel reappears.
     - Re-run verification (return to Step F.2).
   - **Fail, root cause is NOT code** (missing env var, missing credential, network issue, missing input data) — fix it yourself with `bash` / `write`. Do not append a FIX TODO and do not submit to the worker. Re-run verification.
4. Cap fix attempts at 3. After 3 consecutive code-fix attempts that still fail, stop the loop and proceed to Step G with a `fail` status.

### Step G. Cleanup and report

1. Kill the long-lived worker session: `process action:kill sessionId:<workerSession>`.
2. Send a final summary to the user with `openclaw message send` (use the notification route captured in Step B). Include:
   - Pass / fail status
   - Path to the generated project (`<projectRoot>/<project-name>/`)
   - Number of coding-agent turns used (1 for the Phase 4 prompt, plus N for fix attempts)
   - If `fail`: the last failure summary so the user knows what to investigate

## Common constraints

- **Never write code yourself.** All code-writing — Phase 4 generation, Phase 5 fixes, Phase 3 probe scripts, anything else — must go through `process:submit` to `<workerSession>` and the TODO list. Do not edit `.py` / `.ts` / `.sh` files with the host's `write` or `edit` tools. (`<projectRoot>/.amphiloop/AGENT_BRIEF.md` and `TODOS.md` are written by the host — those are protocol files, not code.)
- **All worker direction flows through TODOS.md.** Methodology, API references, and bug reports go into `<projectRoot>/.amphiloop/AGENT_BRIEF.md` and `<projectRoot>/.amphiloop/TODOS.md`, not into the prompt. The kickoff prompt and continue prompt are deliberately tiny pointers to those files.
- **One worker, one sessionId, for the whole run.** `<worker>` is chosen once in Step A; `<workerSession>` is opened once in Step E (or earlier in a Step D probe) and reused throughout.
- **Strictly sequential, no concurrent file writes.** The worker handles one prompt at a time. The host writes to TODOS.md only while the worker is sentinel-waiting; the worker writes to TODOS.md only while it is actively working. This is enforced by the sequential prompt/sentinel cycle, so there is no concurrent edit conflict on the file.
- **Sentinel discipline.** Every prompt you submit ends with the requirement to print `### AMPHI-TASK-DONE ###` so you have a deterministic completion signal. If after a generous wait the sentinel has not appeared but the expected files exist and the worker output has been quiet, treat that as completion (sentinel missed) and proceed.
- **Verify the worker actually read the brief.** After the kickoff prompt, scan `process:log` for evidence the worker called its file-read tool on the bridgic-* SKILL.md files listed in AGENT_BRIEF.md. If it skipped them (jumped straight to coding), inject one corrective `process:submit`: "You skipped the brief. STOP and read `.amphiloop/AGENT_BRIEF.md` STEP 1 files now before any further code." This guards against the v6 failure mode of the worker writing wrong APIs.
- **Do not re-implement coding-agent.** Do not write `claude --print '...'` / `codex exec '...'` style bash here — coding-agent's SKILL.md owns spawn details (PTY, background, flags). This skill only tells coding-agent **what** to launch and **how** to drive it via `process:submit`.
- **Progress visibility.** Send a one-line progress note before each `process:submit` so the user can follow the run.
- **Notification deviation.** Tell coding-agent up front this is a long-lived orchestrated session and the orchestrator will summarize at Step G. Do not have the worker self-notify per task.
