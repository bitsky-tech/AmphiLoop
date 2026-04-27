# AmphiLoop

Agent skill & knowledge corpus for the Bridgic ecosystem — providing skills, agents, and commands for building high-quality bridgic projects. Skills cover the foundational specs; commands and agents orchestrate them into end-to-end workflows.

## Architecture

```
AmphiLoop/
├── CLAUDE.md                          ← this file
├── .claude-plugin/
│   └── plugin.json                    ← Claude Code plugin registration
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
├── templates/                         ← static templates read by commands (not auto-scanned by Claude Code)
│   └── build-task-template.md         ← unified TASK.md template (used by /build Phase 1)
├── hooks/                             ← auto-loaded by Claude Code
│   └── hooks.json                     ← hook definitions
└── scripts/
    ├── hook/                          ← hook script implementations
    │   └── inject-command-paths.sh     ← injects PLUGIN_ROOT + PROJECT_ROOT when a bridgic command loads
    ├── run/                           ← runtime scripts used by agents
    │   ├── setup-env.sh               ← verify uv toolchain availability (auto-installs if missing)
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
