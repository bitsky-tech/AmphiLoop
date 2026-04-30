# AmphiLoop

Agent skill & knowledge corpus for the Bridgic ecosystem — providing skills, agents, and commands for building high-quality bridgic projects. Skills cover the foundational specs; commands and agents orchestrate them into end-to-end workflows.

## Architecture

```
AmphiLoop/
├── CLAUDE.md                          ← this file
├── .claude-plugin/
│   ├── plugin.json                    ← Claude Code plugin registration
│   └── marketplace.json               ← marketplace metadata
├── skills/                            ← domain knowledge: "what it is, how to use it"
│   ├── manifest.ini                  ← skill source registry (repo, ref, paths)
│   ├── README.md                      ← manifest docs + auto-generated skill table
│   ├── bridgic-browser/               ← browser automation CLI + SDK
│   ├── bridgic-amphibious/            ← dual-mode agent framework
│   └── bridgic-llms/                  ← LLM providers and initialization
├── agents/                            ← execution methodology: "how to do it well"
│   ├── amphibious-config.md           ← inline-loaded by /build Phase 2 (interactive; NOT a subagent)
│   ├── amphibious-explore.md          ← abstract exploration methodology
│   ├── amphibious-code.md             ← code generation expertise
│   └── amphibious-verify.md           ← project verification expertise
├── commands/                          ← user-invocable workflows (thin orchestrators)
│   └── build.md                       ← /build pipeline (domain-agnostic; accepts --<domain>)
├── domain-context/                    ← pre-distilled per-domain context injected by /build
│   └── browser/                       ← intent.md, config.md, explore.md, code.md, verify.md
│       └── script/                    ← domain-only helpers (e.g. browser-observe.sh)
├── templates/                         ← static templates read by commands (not auto-scanned by Claude Code)
│   └── build-task-template.md         ← unified TASK.md template (used by /build Phase 1)
├── hooks/                             ← auto-loaded by Claude Code
│   └── hooks.json                     ← hook definitions
└── scripts/
    ├── hook/                          ← hook script implementations
    │   └── inject-command-paths.sh     ← injects PLUGIN_ROOT + PROJECT_ROOT when a bridgic command loads
    ├── run/                           ← runtime scripts used by agents
    │   ├── setup-env.sh               ← verify uv toolchain (auto-installs if missing) and run `uv init --bare` in PROJECT_ROOT
    │   ├── check-dotenv.sh            ← .env LLM configuration validation
    │   └── monitor.sh                 ← run-and-monitor for amphibious-verify agent
    └── maintenance/                   ← plugin maintenance scripts (manual)
        └── sync-skills.sh             ← sync skills from source repos via manifest.ini
```

### Component Roles

| Type | Purpose | Example |
|------|---------|---------|
| **Skill** | Domain knowledge reference — loaded on-demand by agents; synced from source repos via `manifest.ini` | bridgic-browser, bridgic-amphibious, bridgic-llms |
| **Agent** | Deep execution methodology — delegated by commands | amphibious-explore, amphibious-code, amphibious-verify |
| **Command** | Multi-step orchestrator invoked by user | /build |
| **Domain Context** | Pre-distilled per-domain rules (`intent.md`, `config.md`, `explore.md`, `code.md`, `verify.md`) injected by `/build` when a domain is selected explicitly via `--<domain>` or auto-detected from `TASK.md` | domain-context/browser |

## Installation

```bash
# Register marketplace (one-time), then install
claude plugin marketplace add bitsky-tech/AmphiLoop
claude plugin install AmphiLoop
```

## Skills

| Skill | When to Use |
|-------|-------------|
| **bridgic-browser** | Browser automation via CLI (`bridgic-browser ...`) or Python SDK (`from bridgic.browser`) |
| **bridgic-amphibious** | Building dual-mode agents with `AmphibiousAutoma`, `CognitiveWorker`, `on_agent`/`on_workflow` |
| **bridgic-llms** | Initializing LLM providers (`OpenAILlm`, `OpenAILikeLlm`, `VllmServerLlm`), configuring `OpenAIConfiguration` |

## Agents

| Agent | When to Use |
|-------|-------------|
| **amphibious-explore** | Systematically explore a target environment via a domain toolset, produce an executable plan with stability-annotated operations |
| **amphibious-code** | Generate a complete bridgic-amphibious project from a task description with optional domain context |
| **amphibious-verify** | Verify a generated amphibious project: inject debug instrumentation, run with monitoring, validate results, clean up |

## Commands

| Command | When to Use |
|---------|-------------|
| **/build** | Unified entry point. Turn any task into a working bridgic-amphibious project. Accepts an optional domain flag (`/build --browser`) to inject pre-distilled context from `domain-context/<domain>/`. Without a flag, auto-detects the domain from `TASK.md` (or falls back to a generic flow). Users may additionally supply their own domain references in `TASK.md`. |

## OpenClaw Integration

The AmphiLoop repository **is** an OpenClaw native plugin. Installing it (`openclaw plugins install <repo> --link`) auto-registers a bundled skill that exposes `/amphiloop_build "<task spec>"` in any OpenClaw chat surface.

| Aspect | How it works |
|--------|--------------|
| **Plugin install** | `openclaw plugins install /abs/path/AmphiLoop-02 --link` then `openclaw gateway restart`. Setup + verification details in `extensions/openclaw-skill/README.md`. |
| **Native classification** | Three small files at repo root — `openclaw.plugin.json` (manifest), `package.json` (with `openclaw.extensions: ["./openclaw-entry.mjs"]`), and `openclaw-entry.mjs` (no-op entry) — make OpenClaw classify AmphiLoop as **native** (`Format: openclaw`) instead of falling back to Claude Code bundle detection from `.claude-plugin/plugin.json`. |
| **Bundled skill** | The plugin manifest declares `"skills": ["./extensions/openclaw-skill"]`; OpenClaw auto-discovers `amphiloop-build/SKILL.md` under that directory. |
| **Orchestration** | The OpenClaw host model drives Phases 2–3 (config + explore) directly, reading the methodology from `agents/amphibious-*.md` via the `{baseDir}/../..` path resolution. |
| **Code generation (host ↔ coding-agent)** | Host writes `<projectRoot>/.amphiloop/AGENT_BRIEF.md` (lists the bridgic-* SKILL.md files the worker MUST read for correct API usage) + `<projectRoot>/.amphiloop/TODOS.md` (task list). Then opens **one** long-lived OpenClaw `coding-agent` session and sends a tiny pointer prompt. Worker reads brief, reads TODOs, completes them, ticks `[ ]` to `[x]`. |
| **Verify-fix loop** | Phase 5 verify failures get **appended** to the same `TODOS.md` as new `[ ] FIX-N: ...` entries; host then sends a one-line "continue" to the same long-lived worker session. Up to 3 fix rounds. |
| **Worker choice** | The skill asks the user at run start which worker to dispatch to (`claude` recommended, plus `codex` / `opencode` / `pi`). One worker per run, reused throughout. |
| **Existing files** | All Claude Code-only artifacts (`hooks/`, `.claude-plugin/`, `commands/build.md`, `scripts/hook/`) remain in place. The new `package.json` + `openclaw-entry.mjs` + `openclaw.plugin.json` are the only repo-root additions; they coexist with the Claude Code manifest without conflict. |
