#!/bin/bash
# Inject PLUGIN_ROOT and PROJECT_ROOT when a bridgic COMMAND is loaded via Skill tool.
#
# Fires on PreToolUse for Skill. Extracts the "skill" field from the JSON input
# and checks if it exactly matches a command filename in this plugin's commands/ dir.
# Only injects paths for bridgic commands — all other skills pass through untouched.
#
# Pure bash + awk — no dependency on python, node, jq, or any runtime.

INPUT=$(cat)
ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# No plugin root — pass through
if [ -z "$ROOT" ]; then
  printf '{}'
  exit 0
fi

# Extract skill name from JSON input: {"tool_input": {"skill": "<name>", ...}}
SKILL_NAME=$(printf '%s' "$INPUT" | awk '
{
  full = full (NR > 1 ? "\n" : "") $0
}
END {
  # Match "skill" : "value" — extract value between quotes
  if (match(full, /"skill"[ \t]*:[ \t]*"([^"]*)"/, arr)) {
    print arr[1]
  }
}')

# No skill name extracted — pass through
if [ -z "$SKILL_NAME" ]; then
  printf '{}'
  exit 0
fi

# Check if skill name matches a command file in this plugin (exact match)
MATCHED=false
if [ -d "$ROOT/commands" ]; then
  for f in "$ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    if [ "$SKILL_NAME" = "$name" ]; then
      MATCHED=true
      break
    fi
  done
fi

if [ "$MATCHED" = false ]; then
  printf '{}'
  exit 0
fi

# Print resolved paths to stderr — Claude sees stderr as additional context
cat >&2 <<EOF
---
PLUGIN_ROOT=${ROOT}
PROJECT_ROOT=${PWD}
Use these as path prefixes: {PLUGIN_ROOT}/scripts/..., {PLUGIN_ROOT}/skills/..., {PROJECT_ROOT}/.bridgic/...
---
EOF

printf '{}'
exit 0
