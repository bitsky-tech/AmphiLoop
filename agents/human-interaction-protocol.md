---
name: human-interaction-protocol
description: >-
  Shared methodology for any AmphiLoop orchestrator or agent that needs to
  pause and ask the human user during the build pipeline (Phases 1–5 of
  /build, equivalently Steps B–F of the OpenClaw amphiloop-build skill).
  Defines a capability-tiered fallback (structured ask tool → free-text
  channel → escalate to parent), the phase-checkpoint pattern that keeps the
  user in control between major pipeline steps, and the anti-patterns
  (notably silent Bash polling) that violate the contract.
---

# Human Interaction Protocol

Every AmphiLoop pipeline shares one non-negotiable contract:

> The user must always **see** what is being asked, must always **explicitly
> reply** before the run advances, and must always be able to **redirect** at
> phase boundaries. No silent waiting. No timeout-driven auto-continue.

This document is the single source of truth. `commands/build.md`, every
`agents/amphibious-*.md`, and `extensions/openclaw-skill/amphiloop-build/SKILL.md`
all defer to the rules below.

## Scope — what this protocol governs

The protocol governs **orchestrator-driven, build-pipeline user interaction**:

- Claude Code: the `/build` command and every agent it dispatches —
  Phase 1 (Init) → Phase 2 (Config) → Phase 3 (Explore) → Phase 4 (Code) →
  Phase 5 (Verify, including the first instrumented test-run of the freshly
  generated code).
- OpenClaw: the `amphiloop-build` skill and its host orchestration —
  Steps B → C → D → E0/E → F → G.

All five phases are construction-phase: the orchestrator is driving, the user
is a *co-designer*, and the user must be able to see/steer at every meaningful
moment.

**Out of scope**: once the build finishes and the user takes the generated
project and runs `uv run python main.py` themselves (or wires it into their
own CI/cron/etc.), any human interaction the program performs at that point
is **runtime business logic** owned by the bridgic framework's default
`HumanCall` mechanism. The protocol does not govern that channel.

### Note on Phase 5's runtime file-bridge

Phase 5 (verify) injects a `human_input` override and runs the program under
`monitor.sh`. When the program yields a `HumanCall` mid-execution, a file
bridge transports the prompt from the running program back up to the
orchestrator. **That bridge is a transport mechanism, not a protocol tier.**
Once the prompt arrives at the orchestrator (the verify agent in Claude Code,
or the OpenClaw host), the orchestrator is now in Tier 1 or Tier 2 and asks
the user using the rules below — the bridge does not absolve the orchestrator
of applying the protocol.

## Capability tiers — pick the first that applies in your runtime

### Tier 1 — Structured ask tool available

If the runtime exposes a structured-question tool (Claude Code's
`AskUserQuestion`, or any platform equivalent that pops a labeled-options UI),
**use it directly**. Phrase the question with explicit numbered options.

Do **not** also emit the same question as plain chat text alongside the tool
call — the question is sent once, through the tool.

**Option-construction rules** (apply to every Tier 1 ask):

- **Header is hard-capped — keep it ≤12 characters.** Claude Code's
  `AskUserQuestion` UI truncates long headers and the truncation tail can
  surface as garbled output (e.g. `Phase 1→2876…`). Treat the header as a
  tab label, not a sentence: `Phase 1→2`, `Continue?`, `LLM mode`,
  `Domain?`. If you can't fit the meaning in 12 characters, the meaning
  belongs in the question body, not the header.
- **Don't duplicate the always-available free-text channel as an explicit
  option.** `AskUserQuestion` (and most equivalents) already render a
  permanent free-text input row beneath the structured options ("Chat about
  this" in Claude Code). Adding a structured option whose action is "type
  something" / "free input" / "describe in chat" is pure noise — that
  channel is open by default. Reserve structured options for the *distinct
  branches the orchestrator must commit to*.
- **Use however many options the decision actually has — don't pad.** If
  there are only two real branches, ship two options. If you find yourself
  adding a third option just to reach a round number and its content is
  vague ("Type something", "Other", "Anything else"), delete it. A
  meaningful third option looks like an escape hatch (`Cancel build`,
  `Skip this check`, `Abort and revisit later`), not a filler.
- **Each option's description must add information beyond its label** —
  what concretely happens next, what the user should reply, what side
  effect kicks in. Do not paraphrase the label in slightly different words;
  if you can delete the description without losing meaning, you wrote it
  wrong.
- **Option descriptions must NOT re-state the pre-question summary.** The
  summary above the AskUserQuestion already established context (what just
  finished, what's coming, side effects). The option description's job is
  to say what is **unique** to choosing *this* branch — typically one short
  clause: `→ runs setup-env.sh now`, `→ stays on the menu`, `→ aborts the
  build`. If two branches' descriptions both rehearse the same upcoming
  pipeline outline, you wrote the summary into the options. Delete the
  duplication; trust the summary.

### Tier 2 — Free-text reply channel available

The runtime can send the user a normal chat / message and receive a free-text
reply (e.g. an OpenClaw host conversation, a chat surface that holds a
`notifyChannel` / `notifyTarget` route). Send a clearly formatted message and
**wait for the user's explicit textual reply** before continuing.

The message MUST:

- Begin with a visible marker — e.g. `[USER ACTION REQUIRED]` or `[CHECKPOINT]`.
- State concretely what the user must do or decide. No paraphrase.
- State exactly how to reply — what word, what file, what click. Examples:
  - "Reply `yes` to continue, or describe what you'd like changed."
  - "Once you finish login in the open browser, reply `done`."
- Stay terse. One screenful max.

### Tier 3 — No direct user channel → escalate to parent

You are running where the user cannot be reached directly (typical case: a
Claude Code dispatchable subagent whose `tools:` list omits `AskUserQuestion`).
In this tier you **MUST** escalate; you **MUST NOT** poll a signal file in
silence and call that "asking the user".

Stop work and return a structured "human input needed" status to the calling
command — include the prompt text, the resume signal the parent should hand
back, and any context the parent needs to ask coherently. The parent runs in a
higher tier (1 or 2) and asks on your behalf, then re-dispatches you with the
answer.

If the agent's job genuinely requires interactive user input mid-task and
escalation is impractical, the cleaner fix is to add `AskUserQuestion` (or
the platform equivalent) to the agent's `tools:` list so it operates in Tier
1 — not to invent a polling workaround.

## Phase checkpoint pattern

At every checkpoint the orchestrator must:

1. Send a short pre-question summary that combines (a) what just finished
   (artifacts written, decisions made) and (b) what the next phase will do
   plus any side effect worth a veto. **Total length cap: 3 visible lines
   maximum across (a)+(b) combined** (not 3 lines per item). If you can't
   fit it in 3 lines, you're describing too much — the user can read
   `build_context.md` if they want detail.
2. The list of "things worth flagging as side effects" — files written,
   env mutated, scripts run, processes spawned, real browsers opened, real
   money / API quota spent, the generated program executed for the first
   time — is a **selection menu, not an enumeration template**. Pick the
   **one or two** items the user is most likely to want to veto on this
   transition; ignore the rest. Do not produce a flowing prose paragraph
   that lists every applicable category.
3. Ask "Continue to <next phase>?" via Tier 1 or Tier 2. The pre-question
   summary lives **above** the question, not duplicated inside option
   descriptions (see Tier 1 option-construction rules).
4. Wait for an explicit affirmative reply (`yes`, `y`, `go`, `continue`)
   before advancing. Anything else (silence, `wait`, `let me look`, a
   counter-question) means **do not advance** — answer the user's intervention
   first and re-prompt the checkpoint when ready.

Checkpoints are cheap when terse — one short summary plus a one-tap question.
Their value is the *option* to redirect, not the friction. A checkpoint that
overflows the visible area defeats its own purpose: the user cannot see the
question they are being asked.

### Length self-check (run mentally before sending)

- Pre-question summary: ≤3 lines? If no → trim.
- AskUserQuestion header: ≤12 chars? If no → trim.
- Each option description: 1 short clause that is **not** in the summary?
  If no → rewrite or delete.
- Total surface (summary + question + 2–3 options): does it fit one screen
  without scrolling? If no → cut the summary first, then the option
  descriptions; the question text itself stays.

**Where to place checkpoints**: at the boundary between major pipeline phases,
and additionally before any single sub-step that has a meaningful side effect
the user might want to veto or adjust — running a setup script that mutates
the toolchain, writing `.env`, spawning a worker process, kicking off a real
run of the generated program, or starting a multi-attempt fix-and-retry loop.
Skip checkpoints inside tight inner loops or for purely informational reads.

## Anti-patterns — never do these

- ❌ `echo "Please do X" && until [ -f /tmp/flag ]; do sleep 3; done` — the
  user only sees a quiet "Running" indicator. They have no idea what is being
  asked or that they are the bottleneck. This is the canonical violation.
- ❌ Auto-continuing after a fixed silence. Silence means the user is busy or
  hasn't seen the request — not consent.
- ❌ Burying the question in a long log dump. The user will scroll past it
  and the run stalls.
- ❌ Asking via Tier 1/2 *and* echoing the same question to a Bash polling
  loop. Pick one channel; the second is noise that masks the real one.
- ❌ Treating the Phase 5 file-bridge as if it were the user channel. The
  bridge ends at the orchestrator; the orchestrator still owes the user a
  Tier 1/2 ask.
- ❌ Padding a Tier 1 ask with a "Type something" / "Other / free input"
  structured option. The free-text input row is always rendered; an
  explicit option pointing to it is redundant and signals to the user that
  the structured options are not load-bearing.
- ❌ Writing an option description that just rephrases its label. Either
  add concrete information (what happens next, how to reply) or drop the
  description.

## Quick decision flowchart

```
Need to ask the user something?
├── Have AskUserQuestion (or equivalent)?       → Tier 1: ask directly.
├── Have a chat / message channel?              → Tier 2: send + await reply.
└── Neither (subagent boundary, no user channel)
                                                → Tier 3: escalate to parent.
```
