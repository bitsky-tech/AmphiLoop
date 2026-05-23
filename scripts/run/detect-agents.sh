#!/bin/bash
# detect-agents.sh — Scan the user's environment for installed coding-agent
# CLIs that bridgic-amphibious can drive (currently: ClaudeCodeAgent → `claude`,
# CodexAgent → `codex`).
#
# AmphiLoop does NOT bundle these CLIs — the user installs them themselves.
# This script only reports what's already present, so the build pipeline's
# Configuration phase can offer the user only the agents they actually have.
#
# Output: a TSV block between `=== AGENTS_DETECTED ===` and
# `=== END AGENTS_DETECTED ===` markers, one line per detected agent:
#
#   <kind>\t<label>\t<binary_path>
#
# An empty body (just the markers) means no agents are installed.
#
# Exit code: always 0 — scanning is informational, never gating.

set -u

echo "=== AGENTS_DETECTED ==="

# Claude Code — drives the `claude` CLI.
if command -v claude &>/dev/null; then
    printf 'claude_code\tClaude Code\t%s\n' "$(command -v claude)"
fi

# Codex — drives the `codex` CLI. On macOS the Codex.app bundle installs the
# binary at a fixed internal path but does NOT add it to PATH; bridgic's
# CodexAgent accepts either via its `bin` arg, so we fall back to that path.
if command -v codex &>/dev/null; then
    printf 'codex\tCodex\t%s\n' "$(command -v codex)"
elif [ -x "/Applications/Codex.app/Contents/Resources/codex" ]; then
    printf 'codex\tCodex\t%s\n' "/Applications/Codex.app/Contents/Resources/codex"
fi

echo "=== END AGENTS_DETECTED ==="
