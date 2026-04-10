#!/bin/bash
# setup-env.sh — Check uv availability and initialize a uv project.
#
# 1. Checks if uv is on PATH. If not, prints install instructions and exits 1.
# 2. Runs `uv init` in the working directory if pyproject.toml is absent.
#
# Usage:
#   setup-env.sh [PROJECT_DIR]   (defaults to current directory)
#
# Exit codes:
#   0  uv available and pyproject.toml present
#   1  uv not installed
#   2  uv init failed

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# ──────────────────────────────────────────────
# 1. Check uv
# ──────────────────────────────────────────────
if ! command -v uv &>/dev/null; then
    echo "ERROR: uv is not installed."
    echo "Install it via: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

echo "uv: $(uv --version 2>&1)"

# ──────────────────────────────────────────────
# 2. Initialize uv project (if pyproject.toml is absent)
# ──────────────────────────────────────────────
if [ ! -f pyproject.toml ]; then
    echo "No pyproject.toml found — running uv init ..."
    uv init || { echo "Error: uv init failed."; exit 2; }
    echo "Created pyproject.toml"
else
    echo "pyproject.toml already exists, skipping init"
fi

echo ""
echo "=== ENV_READY ==="
echo "uv: $(uv --version 2>&1)"
echo "project_dir: $(pwd)"
