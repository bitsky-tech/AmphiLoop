# Hooks

Hooks are event-driven automations that fire before or after Claude Code tool executions. In this plugin, hooks solve infrastructure concerns that should not pollute skill, agent, or command content.

## How Hooks Work

```
User request → Claude picks a tool → PreToolUse hook runs → Tool executes → PostToolUse hook runs
```

- **PreToolUse** hooks run before the tool executes. They can **block** (exit code 2), **warn** (stderr), or **modify tool input** (`updatedInput`).
- **PostToolUse** hooks run after the tool completes. They can analyze output but cannot block.
- **Stop** hooks run after each Claude response.

Claude Code automatically loads `hooks/hooks.json` from any installed plugin — no registration in `plugin.json` required.

## Hooks in This Plugin

### PreToolUse Hooks

| Hook | Matcher | What It Does | Script |
|------|---------|-------------|--------|
| **Command path injection** | `Skill` | Injects `PLUGIN_ROOT` and `PROJECT_ROOT` via stderr when a bridgic command is loaded | `scripts/hook/inject-command-paths.sh` |

### Why Command Path Injection?

Commands need two resolved paths to locate plugin assets and project output directories. The hook fires only for skills that match a command filename in `commands/*.md`, prints the paths to **stderr** (visible to Claude as context), and the main agent passes them to subagents in delegation prompts.

| Variable | Source | Purpose |
|----------|--------|---------|
| `PLUGIN_ROOT` | `$CLAUDE_PLUGIN_ROOT` | Locate scripts, skills, and command references within this plugin |
| `PROJECT_ROOT` | `$PWD` | Locate project output directories (`.bridgic/explore/`, `.bridgic/browser/`, etc.) |

```
---
PLUGIN_ROOT=/absolute/path/to/AmphiLoop
PROJECT_ROOT=/absolute/path/to/user-project
Use these as path prefixes: {PLUGIN_ROOT}/scripts/..., {PLUGIN_ROOT}/skills/..., {PROJECT_ROOT}/.bridgic/...
---
```

## Adding a New Hook

1. Write the script in the appropriate `scripts/` subdirectory:
   - `scripts/hook/` — hook script implementations (e.g., plugin root injection)
   - `scripts/<domain>/` — domain-specific hooks (create as needed)

2. Register it in `hooks.json`:

```json
{
  "matcher": "ToolName",
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/<subdir>/<script>.sh\""
    }
  ],
  "description": "What this hook does"
}
```

3. `${CLAUDE_PLUGIN_ROOT}` is automatically set by Claude Code to the plugin's root directory.

## Hook Script Conventions

- **Input**: JSON on stdin (tool name, tool input, session info)
- **Output**: JSON on stdout
- **Exit codes**: `0` = success, `2` = block (PreToolUse only), other non-zero = error (logged, does not block)
- **Error handling**: Always exit `0` on non-critical failures — never block tool execution unexpectedly
- **Stderr**: Use for warnings visible to Claude but non-blocking

## Related

- [scripts/hook/](../scripts/hook/) — Hook script implementations
- [CLAUDE.md](../CLAUDE.md) — Plugin architecture overview
