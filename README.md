# AmphiLoop

English | [中文](README-zh.md)

Agent skill & knowledge corpus for the [Bridgic](https://github.com/bitsky-tech) ecosystem — a corpus that provides skills, agents, and commands for building projects powered by LLM-driven and deterministic dual-mode execution.

## What is AmphiLoop?

AmphiLoop is a **Corpus** that packages domain knowledge and execution methodology into three layers:

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

Commands are user-invocable workflows. Type them directly:

#### `/build-browser`

```
/build-browser

Task: Go to https://example.com, search for "product", and extract the first 5 results
```

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
| **bridgic-basic** | Working with Bridgic core framework (Worker, Automa, GraphAutoma, ASL) |
| **bridgic-browser** | Using browser automation via CLI (`bridgic-browser ...`) or Python SDK (`from bridgic.browser`) |
| **bridgic-browser-agent** | Building browser automation agents with OOP patterns and dynamic ref resolution |
| **bridgic-amphibious** | Building dual-mode agents with `AmphibiousAutoma`, `CognitiveWorker`, `on_agent`/`on_workflow` |
| **bridgic-llms** | Initializing LLM providers (`OpenAILlm`, `OpenAILikeLlm`, `VllmServerLlm`) |

## Architecture

```
AmphiLoop/
├── .claude-plugin/
│   └── plugin.json              # Plugin registration
├── skills/                      # Domain knowledge (5 skills)
│   ├── bridgic-basic/           #   Core framework concepts
│   ├── bridgic-browser/         #   Browser automation CLI + SDK
│   ├── bridgic-browser-agent/   #   Browser agent patterns
│   ├── bridgic-amphibious/      #   Dual-mode agent framework
│   └── bridgic-llms/            #   LLM provider integration
├── agents/                      # Execution methodology (3 agents)
│   ├── browser-explorer.md      #   CLI exploration expert
│   ├── amphibious-generator.md  #   Code generation expert
│   └── amphibious-verify.md     #   Project verification expert
├── commands/                    # User-invocable workflows
│   ├── build-browser.md         #   End-to-end pipeline
│   └── references/
│       └── build-browser-code-patterns.md
├── hooks/                       # Auto-loaded event handlers
│   └── hooks.json
└── scripts/                     # Hook & utility implementations
    ├── hook/
    │   └── inject-command-paths.sh
    └── run/
        ├── setup-env.sh            #   Environment setup (uv, deps, playwright)
        ├── check-dotenv.sh         #   LLM configuration validation
        └── monitor.sh
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

## License

See [LICENSE](LICENSE) for details.
