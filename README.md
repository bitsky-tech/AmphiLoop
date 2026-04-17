# AmphiLoop

English | [中文](README-zh.md)

AmphiLoop, short for Amphibious Loop, is a new methodology, technology stack, and toolchain for building AI agents. It enables tasks to be described and orchestrated using natural language, with an “Explore → Code → Verify” loop guiding code generation and build. The resulting artifacts are capable of automatically switching between workflow mode and agent mode at runtime.

AmphiLoop packages domain knowledge and execution methodology into three layers:

| Layer | Role | Description |
|-------|------|-------------|
| **Skills** | Domain knowledge | "What it is, how to use it" — reference docs loaded on-demand |
| **Agents** | Execution methodology | "How to do it well" — specialized execution experts |
| **Commands** | Orchestration | Multi-step workflows that coordinate agents and skills |

Together, they enable an end-to-end pipeline: **explore a website via CLI** -> **generate a dual-mode agent project** -> **verify execution** — all within an agent.

## Installation

```bash
# Step 1: Register the marketplace (one-time)
claude plugin marketplace add bitsky-tech/AmphiLoop

# Step 2: Install the plugin
claude plugin install AmphiLoop
```

Or install directly from a local checkout:

```bash
git clone https://github.com/bitsky-tech/AmphiLoop.git
claude plugin install /path/to/AmphiLoop
```

After installation, skills, agents, and commands (e.g. `/build-browser`) are automatically available in Claude Code.

## Usage

### Commands

Commands are user-invocable workflows. Invoke them with the `/` prefix:

#### `/AmphiLoop:build-browser`

Describe a browser automation task and ask to generate a stable, runnable project:

```
/AmphiLoop:build-browser

Go to https://example.com, search for "product", and extract the first 5 results.
I want a project that can run this reliably.
```

Your input should contain two key intents:
1. **A browser automation task** — what to do on the target website (navigate, click, extract, etc.)
2. **A request to generate a stable project** — you want a working program/project that can run reliably

**What happens under the hood:**

1. **Parse** — Extracts URL, goal, and expected output from your task description
2. **Setup** — Checks environment (uv, dependencies, `.env`)
3. **Explore** — Delegates to `browser-explorer` agent to systematically explore the target website via CLI
4. **Generate** — Delegates to `amphibious-generator` agent to produce a complete project with all source files
5. **Verify** — Delegates to `amphibious-verify` agent to inject debug instrumentation, run the project, and validate results

### Agents

Agents are execution specialists delegated by commands. They are not called directly by users but are orchestrated internally:

| Agent | What It Does |
|-------|-------------|
| **browser-explorer** | Systematically explores a website via CLI, produces a structured exploration report with snapshots |
| **amphibious-generator** | Generates a complete bridgic-amphibious project from a task description and exploration report |
| **amphibious-verify** | Injects debug instrumentation, runs the project with monitoring, validates results, and cleans up |

### Skills

Skills are domain knowledge references that agents and Claude load automatically when relevant. You don't invoke them directly — they activate based on conversation context.

| Skill | Activates When |
|-------|---------------|
| **bridgic-browser** | Using browser automation via CLI (`bridgic-browser ...`) or Python SDK (`from bridgic.browser`) |
| **bridgic-amphibious** | Building dual-mode agents with `AmphibiousAutoma`, `CognitiveWorker`, `on_agent`/`on_workflow` |
| **bridgic-llms** | Initializing LLM providers (`OpenAILlm`, `OpenAILikeLlm`, `VllmServerLlm`) |

## Architecture

```
AmphiLoop/
├── .claude-plugin/
│   ├── plugin.json              # Plugin registration
│   └── marketplace.json         # Marketplace metadata
├── skills/                      # Domain knowledge (3 skills)
│   ├── manifest.ini             #   Skill source registry (repo, ref, paths)
│   ├── README.md                #   Manifest docs + auto-generated skill table
│   ├── bridgic-browser/         #   Browser automation CLI + SDK
│   ├── bridgic-amphibious/      #   Dual-mode agent framework
│   └── bridgic-llms/            #   LLM provider integration
├── agents/                      # Execution methodology (3 agents)
│   ├── browser-explorer.md      #   CLI exploration expert
│   ├── amphibious-generator.md  #   Code generation expert
│   └── amphibious-verify.md     #   Project verification expert
├── commands/                    # User-invocable workflows
│   └── build-browser.md         #   End-to-end pipeline
├── examples/                    # Static example docs (not auto-scanned)
│   ├── build-browser-code-patterns.md
│   └── build-browser-task-template.md
├── hooks/                       # Auto-loaded event handlers
│   └── hooks.json
└── scripts/                     # Hook & utility implementations
    ├── hook/
    │   └── inject-command-paths.sh
    ├── run/
    │   ├── setup-env.sh         #   Environment setup (uv, deps, playwright)
    │   ├── check-dotenv.sh      #   LLM configuration validation
    │   └── monitor.sh
    └── maintenance/
        └── sync-skills.sh       #   Sync skills from source repos via manifest.ini
```

### How the Layers Connect

```
User invokes command
        |
        v
  +-----------+        reads       +--------+
  |  Command  | -----------------> | Skills |
  +-----------+                    +--------+
        |
        | delegates to
        v
  +-----------+        reads       +--------+
  |  Agents   | -----------------> | Skills |
  +-----------+                    +--------+
        |
        | uses
        v
  +-----------+
  |   Hooks   |  (inject plugin context into subagent prompts)
  +-----------+
```

### Community

Join us to share feedback, ask questions, and keep up with what's new:

- 🐦 Twitter / X: [@bridgic](https://x.com/bridgic)
- 💬 Discord: [Join our server](https://discord.gg/4NyKjXGKEh)

## License

See [LICENSE](LICENSE) for details.
