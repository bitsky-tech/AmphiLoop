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

## Further Reading

Long-form pieces on the motivation and design philosophy behind AmphiLoop:

[Beyond Autonomous: Why I'm Building an Amphibious Agent](https://pub.towardsai.net/beyond-autonomous-why-im-building-an-amphibious-agent-fcae9a409220)

## Installation

```bash
# Step 1: Register the marketplace (one-time)
claude plugin marketplace add bitsky-tech/AmphiLoop

# Step 2: Install the plugin
claude plugin install AmphiLoop
```

Or install from a local checkout (point `marketplace add` at the local directory — it's read as a marketplace because the repo ships `.claude-plugin/marketplace.json`):

```bash
git clone https://github.com/bitsky-tech/AmphiLoop.git
claude plugin marketplace add /path/to/AmphiLoop
claude plugin install AmphiLoop
```

After installation, skills, agents, and commands (e.g. `/build`) are automatically available in Claude Code.

## Usage

### Commands

Commands are user-invocable workflows. Invoke them with the `/` prefix:

#### `/AmphiLoop:build`

Unified pipeline. Describe any task, list the domain references the agents should read (SKILLs, CLI help, SDK docs, style guides), and ask to generate a runnable project:

```
/AmphiLoop:build

I want to aggregate all `orders_*.csv` files under ~/data/inputs into a single
summary.csv — one row per customer with totals.
```

**Domain flag (optional)** — append `--<domain>` to inject pre-distilled domain context from `domain-context/<domain>/`. Currently supported: `--browser`.

```
/AmphiLoop:build --browser

Go to https://example.com, search for "product", and extract the first 5 results.
I want a project that can run this reliably.
```

Without a flag, `/build` auto-detects the domain from `TASK.md` (and falls back to a generic flow if none matches). Users can always supply additional domain references in `TASK.md`.

**What happens under the hood:**

1. **Initialize Task** — Writes a `TASK.md` template where you fill in goal, expected output, and **Domain References**; auto-detects the domain if no flag was given
2. **Configure Pipeline** — Project mode (Workflow vs Amphiflow), LLM config if needed, plus any domain-specific configuration (e.g. browser environment mode when `--browser` is active)
3. **Setup Environment** — Checks `uv`, runs `uv init`
4. **Explore** — Delegates to `amphibious-explore` agent, which reads your domain references and probes the environment
5. **Generate** — Delegates to `amphibious-code` agent to produce a complete project with all source files
6. **Verify** — Delegates to `amphibious-verify` agent to inject debug instrumentation, run the project, and validate results

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
│   └── build.md                 #   Unified pipeline (accepts optional --<domain> flag)
├── domain-context/              # Pre-distilled per-domain context injected by /build
│   └── browser/                 #   intent.md, config.md, explore.md, code.md, verify.md (+ script/)
├── templates/                   # Static templates read by commands (not auto-scanned)
│   └── build-task-template.md         #   Unified TASK.md template used by /build
├── hooks/                       # Auto-loaded event handlers
│   └── hooks.json
└── scripts/                     # Hook & utility implementations
    ├── hook/
    │   └── inject-command-paths.sh
    ├── run/
    │   ├── setup-env.sh         #   Verify uv toolchain; uv init --bare in PROJECT_ROOT
    │   ├── check-dotenv.sh      #   LLM configuration validation
    │   └── monitor.sh           #   Run-and-monitor for amphibious-verify
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
