#!/bin/bash
# setup-env.sh — Ensure uv is available and PROJECT_ROOT is a uv project.
#
# 1. Checks uv is on PATH; auto-installs it on macOS/Linux/Windows if missing.
# 2. Runs `uv init --bare` in PROJECT_DIR if no pyproject.toml is present.
# 3. Prints an ENV_READY block followed by the verbatim pyproject.toml so
#    callers see exactly which packages and dependencies the shared uv env
#    currently has.
#
# After this script exits 0, PROJECT_DIR is a uv project (pyproject.toml +
# .venv ready to grow). Per-skill `install-deps.sh` scripts and the
# amphibious-code agent then `uv add` their packages into this same env —
# the project-level uv env is shared across all later phases.
#
# Usage:
#   setup-env.sh [PROJECT_DIR]   (defaults to current directory)
#
# Exit codes:
#   0  uv available and pyproject.toml present
#   1  uv installation failed
#   2  uv init failed

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# ──────────────────────────────────────────────
# 1. Ensure uv is installed
# ──────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
    echo "uv not found — installing ..."
    case "$(uname -s)" in
        CYGWIN*|MINGW*|MSYS*|Windows_NT*)
            # Windows (Git Bash / MSYS2 / Cygwin)
            powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex" \
                || { echo "Error: uv installation failed on Windows."; exit 1; }
            ;;
        *)
            # macOS / Linux / other Unix-like
            curl -LsSf https://astral.sh/uv/install.sh | sh \
                || { echo "Error: uv installation failed."; exit 1; }
            ;;
    esac

    # Reload PATH so the current shell can find uv
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    if ! command -v uv &>/dev/null; then
        echo "Error: uv was installed but not found on PATH."
        echo "You may need to restart your shell or add ~/.local/bin to PATH."
        exit 1
    fi

    echo "uv installed successfully."
fi

echo "uv: $(uv --version 2>&1)"

# ──────────────────────────────────────────────
# 2. Initialize uv project (bare — no main.py / README scaffolding)
# ──────────────────────────────────────────────
if [ ! -f pyproject.toml ]; then
    echo "No pyproject.toml found — running uv init --bare ..."
    uv init --bare || { echo "Error: uv init failed."; exit 2; }
    echo "Created pyproject.toml"
else
    echo "pyproject.toml already exists, skipping init"
fi

echo ""
echo "=== ENV_READY ==="
echo "uv: $(uv --version 2>&1)"
echo "project_dir: $(pwd)"
echo "--- pyproject.toml ---"
cat pyproject.toml
