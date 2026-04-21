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

Commands are user-invocable workflows. Invoke them with the `/` prefix:

#### `/AmphiLoop:build`

Domain-agnostic pipeline. Describe any task, list the domain references the agents should read (SKILLs, CLI help, SDK docs, style guides), and ask to generate a runnable project:

```
/AmphiLoop:build

I want to aggregate all `orders_*.csv` files under ~/data/inputs into a single
summary.csv — one row per customer with totals.
```

**What happens under the hood:**

1. **Initialize Task** — Writes a `TASK.md` template where you fill in goal, expected output, and **Domain References**
2. **Configure Pipeline** — Project mode (Workflow vs Amphiflow) and LLM config if needed
3. **Setup Environment** — Checks `uv`, runs `uv init`
4. **Explore** — Delegates to `amphibious-explore` agent, which reads your domain references and probes the environment
5. **Generate** — Delegates to `amphibious-code` agent to produce a complete project with all source files
6. **Verify** — Delegates to `amphibious-verify` agent to inject debug instrumentation, run the project, and validate results

#### `/AmphiLoop:build-browser`

Browser-domain specialization of `/build`. Pre-distills the browser domain context (observation protocol, code patterns, verification rules) so you only need to describe the browser automation task:

```
/AmphiLoop:build-browser

Go to https://example.com, search for "product", and extract the first 5 results.
I want a project that can run this reliably.
```

Your input should contain two key intents:
1. **A browser automation task** — what to do on the target website (navigate, click, extract, etc.)
2. **A request to generate a stable project** — you want a working program/project that can run reliably

The under-the-hood phases mirror `/build`, but Phase 2 also asks about browser environment mode (Default vs Isolated), and Phases 4–6 pass pre-distilled browser-specific domain context to the agents.

### Agents

Agents are execution specialists delegated by commands. They are not called directly by users but are orchestrated internally:

| Agent | What It Does |
|-------|-------------|
| **amphibious-explore** | Systematically explores a target environment via a domain-supplied toolset, produces an executable plan with stability-annotated operations and supporting snapshots |
| **amphibious-code** | Generates a complete bridgic-amphibious project from a task description and exploration report |
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
│   ├── amphibious-explore.md    #   Abstract exploration methodology
│   ├── amphibious-code.md       #   Code generation expert
│   └── amphibious-verify.md     #   Project verification expert
├── commands/                    # User-invocable workflows
│   ├── build.md                 #   Domain-agnostic pipeline
│   └── build-browser.md         #   Browser-domain pipeline
├── templates/                   # Static templates read by commands (not auto-scanned)
│   ├── build-task-template.md         #   Unified TASK.md template for /build and /build-browser
│   └── build-browser-code-patterns.md #   Browser-specific code patterns
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
