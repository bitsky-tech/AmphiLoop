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
│   ├── browser-explorer.md            ← CLI exploration expertise
│   ├── amphibious-generator.md        ← code generation expertise
│   └── amphibious-verify.md           ← project verification expertise
├── commands/                          ← user-invocable workflows (thin orchestrators)
│   └── build-browser.md               ← /build-browser pipeline
├── examples/                          ← static example docs (not auto-scanned by Claude Code)
│   └── build-browser-code-patterns.md ← browser-specific code patterns
├── hooks/                             ← auto-loaded by Claude Code
│   ├── hooks.json                     ← hook definitions
│   └── README.md                      ← hook system documentation
└── scripts/
    ├── hook/                          ← hook script implementations
    │   └── inject-command-paths.sh     ← injects PLUGIN_ROOT + PROJECT_ROOT when a bridgic command loads
    ├── run/                           ← runtime scripts used by agents
    │   ├── setup-env.sh               ← auto-install uv + uv init --bare
    │   ├── check-dotenv.sh            ← .env LLM configuration validation
    │   └── monitor.sh                 ← process monitor for amphibious-verify agent
    └── maintenance/                   ← plugin maintenance scripts (manual)
        └── sync-skills.sh             ← sync skills from source repos via manifest.ini
```

### Component Roles

| Type | Purpose | Example |
|------|---------|---------|
| **Skill** | Domain knowledge reference — loaded on-demand by agents; synced from source repos via `manifest.ini` | bridgic-browser, bridgic-amphibious, bridgic-llms |
| **Agent** | Deep execution methodology — delegated by commands | browser-explorer, amphibious-generator, amphibious-verify |
| **Command** | Multi-step orchestrator invoked by user | /build-browser |

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
| **browser-explorer** | Systematically explore a website via CLI, produce structured exploration report |
| **amphibious-generator** | Generate a complete bridgic-amphibious project from a task description with optional domain context |
| **amphibious-verify** | Verify a generated amphibious project: inject debug instrumentation, run with monitoring, validate results, clean up |

## Commands

| Command | When to Use |
|---------|-------------|
| **/build-browser** | Turn a browser task into a working bridgic-amphibious project (parse → explore → generate → verify) |
