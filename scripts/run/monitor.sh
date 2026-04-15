#!/bin/bash
# monitor.sh — Lightweight process monitor for amphibious-verify agent.
#
# Polls a running program's PID and log file. Returns control to the
# calling agent only when an actionable event occurs, keeping LLM
# inference costs at zero during normal execution.
#
# Usage:
#   monitor.sh <PID> <LOG_FILE> <VERIFY_DIR> [TIMEOUT_SECONDS]
#
# Exit codes:
#   0  Program finished successfully (no errors in log)
#   1  Program finished with errors (traceback/ERROR in log)
#   2  Human intervention required (human_request.json appeared)
#   3  Timeout — program exceeded allowed runtime
#
# On exit, the last N lines of the log are printed to stdout for
# the agent to read without needing a separate file read.

set -euo pipefail

PID="${1:?Usage: monitor.sh <PID> <LOG_FILE> <VERIFY_DIR> [TIMEOUT]}"
LOG_FILE="${2:?Usage: monitor.sh <PID> <LOG_FILE> <VERIFY_DIR> [TIMEOUT]}"
VERIFY_DIR="${3:?Usage: monitor.sh <PID> <LOG_FILE> <VERIFY_DIR> [TIMEOUT]}"
MAX_TIMEOUT=300
TIMEOUT="${4:-300}"
if [ "$TIMEOUT" -gt "$MAX_TIMEOUT" ]; then
    TIMEOUT="$MAX_TIMEOUT"
fi

POLL_INTERVAL=3
START_TIME=$(date +%s)

while true; do
    # --- Timeout check ---
    NOW=$(date +%s)
    ELAPSED=$(( NOW - START_TIME ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "=== MONITOR: TIMEOUT after ${TIMEOUT}s ==="
        echo "--- Last 30 lines of log ---"
        tail -30 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
        exit 3
    fi

    # --- Human intervention check ---
    if [ -f "${VERIFY_DIR}/human_request.json" ]; then
        echo "=== MONITOR: HUMAN_INTERVENTION_REQUIRED ==="
        cat "${VERIFY_DIR}/human_request.json"
        exit 2
    fi

    # --- Process liveness check ---
    if ! ps -p "$PID" > /dev/null 2>&1; then
        # Process ended — check log for errors
        if grep -qE "Traceback|ERROR|Exception" "$LOG_FILE" 2>/dev/null; then
            echo "=== MONITOR: PROGRAM_ERROR ==="
            echo "--- Last 50 lines of log ---"
            tail -50 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
            exit 1
        else
            echo "=== MONITOR: PROGRAM_FINISHED ==="
            echo "--- Last 30 lines of log ---"
            tail -30 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
            exit 0
        fi
    fi

    sleep "$POLL_INTERVAL"
done
