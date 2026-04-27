#!/bin/bash
# setup-env.sh — Verify the uv toolchain is available.
#
# PROJECT_ROOT is just a workspace (holds TASK.md and .bridgic/); the actual
# uv project lives inside the generated subdirectory <project-name>/, which
# is initialised later by the amphibious-code agent via the bridgic-amphibious
# skill's install-deps.sh. This script only checks that uv is on PATH (auto-
# installs it if not) so amphibious-code can run later without surprises.
#
# Usage:
#   setup-env.sh
#
# Exit codes:
#   0  uv available
#   1  uv installation failed

set -euo pipefail

# ──────────────────────────────────────────────
# Ensure uv is installed
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

echo ""
echo "=== ENV_READY ==="
echo "uv: $(uv --version 2>&1)"
