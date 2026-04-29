#!/bin/bash
# monitor.sh — Run-and-monitor for amphibious-verify agent.
#
# On first call: launches `uv run python main.py` in <WORK_DIR>, captures the
# PID, then enters the monitor loop. On subsequent calls (e.g., after the agent
# handled a human-intervention pause): detects the existing PID and resumes
# monitoring without restarting the program.
#
# Returns control to the caller only when an actionable event occurs, keeping
# LLM inference cost at zero during normal execution.
#
# Usage:
#   monitor.sh <WORK_DIR> [TIMEOUT_SECONDS]
#
# The script owns all runtime artifacts under <PROJECT_ROOT>/.bridgic/verify/
# (PROJECT_ROOT = parent of WORK_DIR — the generator project lives at
# <PROJECT_ROOT>/<project-name>/), so verify state sits next to build_context.md
# and explore/ instead of polluting the generator project:
#   run.log              — captured stdout/stderr of the launched program
#   pid                  — PID of the running program (removed on exit)
#   human_request.json   — written by the program when it needs human input
#   human_response.json  — written by the agent to answer a human request
#
# Every exit prints the resolved paths to stdout so the caller never has to
# guess where files live.
#
# Exit codes:
#   0  Program finished successfully (no errors in log)
#   1  Program finished with errors (traceback/ERROR in log)
#   2  Human intervention required (human_request.json appeared)
#   3  Timeout — program exceeded allowed runtime

set -euo pipefail

WORK_DIR="${1:?Usage: monitor.sh <WORK_DIR> [TIMEOUT]}"
MAX_TIMEOUT=300
TIMEOUT="${2:-300}"
if [ "$TIMEOUT" -gt "$MAX_TIMEOUT" ]; then
    TIMEOUT="$MAX_TIMEOUT"
fi

# Derived paths — caller should never need to know these.
# Verify artifacts live under PROJECT_ROOT (= parent of WORK_DIR), not under
# the generator project itself.
PROJECT_ROOT="$(dirname "${WORK_DIR%/}")"
VERIFY_DIR="${PROJECT_ROOT}/.bridgic/verify"
LOG_FILE="${VERIFY_DIR}/run.log"
PID_FILE="${VERIFY_DIR}/pid"

POLL_INTERVAL=3
mkdir -p "$VERIFY_DIR"

print_paths() {
    echo "--- Paths ---"
    echo "work_dir:       $WORK_DIR"
    echo "verify_dir:     $VERIFY_DIR"
    echo "log_file:       $LOG_FILE"
    echo "human_request:  ${VERIFY_DIR}/human_request.json"
    echo "human_response: ${VERIFY_DIR}/human_response.json"
}

# Recursively terminate $1 and all of its descendants.
kill_tree() {
    local parent=$1
    for child in $(pgrep -P "$parent" 2>/dev/null); do
        kill_tree "$child"
    done
    kill "$parent" 2>/dev/null || true
}

# --- Determine PID: resume existing or start fresh ---
PID=""
if [ -f "$PID_FILE" ]; then
    EXISTING_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$EXISTING_PID" ] && ps -p "$EXISTING_PID" > /dev/null 2>&1; then
        PID="$EXISTING_PID"
        echo "=== MONITOR: RESUMING PID=$PID ==="
    else
        rm -f "$PID_FILE"
    fi
fi

if [ -z "$PID" ]; then
    rm -f "${VERIFY_DIR}/human_request.json" "${VERIFY_DIR}/human_response.json"
    : > "$LOG_FILE"
    nohup bash -c "unset VIRTUAL_ENV && cd '$WORK_DIR' && '${BRIDGIC_ARTIFACT_ROOT}/.venv/bin/python3' main.py" >> "$LOG_FILE" 2>&1 &
    PID=$!
    echo "$PID" > "$PID_FILE"
    echo "=== MONITOR: STARTED PID=$PID ==="
fi

START_TIME=$(date +%s)

while true; do
    # --- Timeout check ---
    NOW=$(date +%s)
    ELAPSED=$(( NOW - START_TIME ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        kill_tree "$PID"
        rm -f "$PID_FILE"
        echo "=== MONITOR: TIMEOUT after ${TIMEOUT}s ==="
        print_paths
        echo "--- Last 30 lines of log ---"
        tail -30 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
        exit 3
    fi

    # --- Human intervention check ---
    # Delete the request file before exiting so a quick re-invoke doesn't
    # re-trip on the stale request before the program consumes the response.
    if [ -f "${VERIFY_DIR}/human_request.json" ]; then
        echo "=== MONITOR: HUMAN_INTERVENTION_REQUIRED ==="
        print_paths
        echo "--- human_request.json ---"
        cat "${VERIFY_DIR}/human_request.json"
        rm -f "${VERIFY_DIR}/human_request.json"
        exit 2
    fi

    # --- Process liveness check ---
    if ! ps -p "$PID" > /dev/null 2>&1; then
        rm -f "$PID_FILE"
        if grep -qE "Traceback|ERROR|Exception" "$LOG_FILE" 2>/dev/null; then
            echo "=== MONITOR: PROGRAM_ERROR ==="
            print_paths
            echo "--- Last 50 lines of log ---"
            tail -50 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
            exit 1
        else
            echo "=== MONITOR: PROGRAM_FINISHED ==="
            print_paths
            echo "--- Last 10 lines of log ---"
            tail -10 "$LOG_FILE" 2>/dev/null || echo "(log file not found)"
            exit 0
        fi
    fi

    sleep "$POLL_INTERVAL"
done
