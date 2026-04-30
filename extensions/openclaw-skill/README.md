# AmphiLoop OpenClaw Skill

Drop-in OpenClaw skill that exposes AmphiLoop as the slash command `/amphiloop_build`. The skill orchestrates AmphiLoop's 5-phase pipeline inside OpenClaw and delegates every code-writing step to OpenClaw's built-in `coding-agent` skill (a worker CLI of your choice — Claude Code, Codex, OpenCode, or Pi). Host and worker communicate via shared files in the working directory (`.amphiloop/AGENT_BRIEF.md` + `.amphiloop/TODOS.md`), not by stuffing a giant prompt.

## Install model

The AmphiLoop repository **is** the OpenClaw plugin. Mounting the repository as a plugin (one command) automatically registers this bundled skill:

1. Clone the AmphiLoop repo somewhere on disk.
2. `openclaw plugins install <repo-path> --link` — see Install below.
3. The skill resolves the AmphiLoop repo root automatically using the OpenClaw `{baseDir}` macro (`{baseDir}/../..`). Users do not need to provide an AmphiLoop path.

There is intentionally no auto-download / clawhub install path — the skill is colocated with the AmphiLoop methodology files (`agents/amphibious-*.md`, `scripts/run/*.sh`, `domain-context/*`, and the bridgic-* SDK skills under `skills/`) it needs at runtime, so they always travel together with the repo clone.

## Dependencies

You must have at least one of the following coding-agent worker CLIs installed and reachable on `PATH`:

- **Claude Code** *(recommended)* — `npm install -g @anthropic-ai/claude-code`
- Codex — `npm install -g @openai/codex`
- OpenCode — see project docs
- Pi — `npm install -g @mariozechner/pi-coding-agent`

OpenClaw's `coding-agent` skill must also be enabled in your OpenClaw config (`skills.entries.coding-agent.enabled: true`).

## Install (recommended: as an OpenClaw plugin)

```bash
# 1. Enable the built-in coding-agent skill we delegate to
openclaw config set skills.entries.coding-agent.enabled true --strict-json

# 2. Install the AmphiLoop repo as a linked openclaw plugin
#    (--link points at your local clone instead of copying — edits to
#     SKILL.md / agents/* / scripts/* are picked up live)
openclaw plugins install /abs/path/to/AmphiLoop-02 --link

# 3. Restart so the gateway loads the plugin
openclaw gateway restart
```

That registers the bundled skill `amphiloop-build` automatically — no `skills.load.extraDirs` entry needed.

> **Note on plugin classification.** AmphiLoop ships both `openclaw.plugin.json` (OpenClaw native manifest) and `.claude-plugin/plugin.json` (the original Claude Code marker). For OpenClaw to classify the repo as a **native** plugin (not as a Claude Code bundle), it also needs `package.json` with `openclaw.extensions: ["./openclaw-entry.mjs"]` plus the tiny `openclaw-entry.mjs` no-op entry. Both files live at the AmphiLoop repo root and are committed.

### Fallback: mount only this skill via `extraDirs` (no plugin)

If you don't want a plugin install, you can mount just this skill directory:

```bash
openclaw config set skills.load.extraDirs \
  '["/abs/path/to/AmphiLoop-02/extensions/openclaw-skill"]' \
  --strict-json --merge
openclaw gateway restart
```

The skill works the same; you just lose the `openclaw plugins enable/disable/inspect/list` lifecycle controls.

## Verification

```bash
# Plugin should be Format: openclaw, Status: loaded
openclaw plugins inspect amphiloop

# Skill should be ✓ Ready
openclaw skills info amphiloop-build

# Cross-check that coding-agent itself is also Ready
openclaw skills check 2>&1 | grep coding-agent
```

After both are ready, the slash command `/amphiloop_build` is live in any OpenClaw chat surface.

## Usage

In an OpenClaw chat:

```
/amphiloop_build "<your task spec>"
```

What happens next:

1. The skill asks you to pick the coding worker for this run (`claude` / `codex` / `opencode` / `pi`). Reply with one word.
2. The skill asks for `<projectRoot>` (where the generated project will live; offers a sensible default).
3. The skill drives Phases 2–3 (config + explore) directly using the OpenClaw host model. Outputs land at `<projectRoot>/.bridgic/build_context.md` and `<projectRoot>/.bridgic/exploration/exploration_report.md`.
4. **The skill writes the worker brief and TODO list** to `<projectRoot>/.amphiloop/AGENT_BRIEF.md` and `<projectRoot>/.amphiloop/TODOS.md`. The brief tells the worker which bridgic-* SKILL.md files to read so the API surface is correct; the TODO list is the work plan.
5. The skill opens **one** long-lived `coding-agent` session with the worker you picked, sends a tiny pointer prompt ("read AGENT_BRIEF.md, read TODOS.md, work through them"), and watches the worker tick TODOs to `[x]`.
6. Phase 5 verifies the generated project. If verification fails because of a code defect, the skill **appends new FIX entries to TODOS.md** and tells the worker (in the same long-lived session) to continue. Up to 3 fix rounds.
7. The skill closes the worker session and sends you a summary message with the project path and pass/fail status.

## Design notes

- **Communication channel is the working directory, not the prompt.** The kickoff prompt is ~200 chars and only points at `.amphiloop/AGENT_BRIEF.md` + `.amphiloop/TODOS.md`. Methodology, API references, and bug reports all flow through files. Benefit: worker isn't drowned in a giant context blob; host can monitor progress by re-reading TODOS.md; bug fixes are appended TODOs instead of fresh fix prompts.
- **Worker is forced to read the bridgic-* SKILL.md files.** The brief lists them as STEP 1 mandatory reads. Without this, the worker hallucinates APIs that don't exist in the bridgic-amphibious / bridgic-llms / bridgic-browser SDK.
- **Why a single long-lived session?** So the worker carries context from the initial generation into any follow-up fix. Restarting the worker per call would force it to re-derive everything from disk and risks stylistic drift.
- **Why ask the user for the worker?** Worker quality varies by task. Claude Code is the closest fit to AmphiLoop's coding methodology and is the recommended default; the others are available for users who prefer them.
- **Why does the skill never write code itself?** The host model (default Pi) is good at orchestration but weaker at sustained coding. All code production is routed to a worker that is purpose-built for it.
- **No write-conflict on TODOS.md.** Host writes to it only while the worker is sentinel-waiting (between turns); worker writes to it only while actively working. The sequential prompt/sentinel cycle enforces this.

## Reference

- AmphiLoop skill source: `extensions/openclaw-skill/amphiloop-build/SKILL.md`
- OpenClaw native plugin manifest: `<repo-root>/openclaw.plugin.json`, `<repo-root>/package.json`, `<repo-root>/openclaw-entry.mjs`
- OpenClaw built-in skill we delegate to: `<openclaw-repo>/skills/coding-agent/SKILL.md`
- OpenClaw slash-command docs: `<openclaw-repo>/docs/tools/slash-commands.md`
- OpenClaw plugin CLI: `openclaw plugins --help`
