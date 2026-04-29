#!/bin/bash
# Inject PLUGIN_ROOT and PROJECT_ROOT when a bridgic COMMAND is being loaded.
#
# A bridgic command can reach Claude via two independent paths:
#
#   (1) User types `/AmphiLoop:build ...` directly.
#       Claude Code expands the command inline as a <command-name> tag in the
#       user turn. No Skill tool call happens — per the Skill tool's own rule,
#       "if you see a <command-name> tag the skill has ALREADY been loaded,
#       follow the instructions directly instead of calling the tool again."
#       → Hook point: UserPromptSubmit. Detect by scanning the `prompt` field
#         for a `/command` token matching one of our commands/*.md files.
#
#   (2) Claude auto-matches the user's natural-language task to a registered
#       skill and invokes `Skill("build")` itself.
#       → Hook point: PreToolUse with matcher "Skill". Detect by reading
#         `tool_input.skill` from the stdin JSON.
#
# Both paths emit an identical additionalContext block via
# hookSpecificOutput.additionalContext on stdout — the only PreToolUse /
# UserPromptSubmit channel that reliably reaches Claude's context. stderr on
# exit 0 is only visible in verbose mode and never reaches Claude.
#
# Pure bash + sed + grep — no dependency on python, node, jq, or any runtime.

INPUT=$(cat)
ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# Authoritative plugin name. MUST match .claude-plugin/plugin.json `name`.
# Used to reject cross-plugin invocations that happen to share a bare command
# name with us (e.g. another plugin exposing `OtherPlugin:build`).
# Without this gate, the hook would run globally and pollute unrelated flows.
PLUGIN_NAME="AmphiLoop"

# No plugin root — pass through
if [ -z "$ROOT" ]; then
  printf '{}'
  exit 0
fi

# Flatten newlines so sed/grep regexes can use `.` reliably.
FLAT=$(printf '%s' "$INPUT" | tr '\n' ' ')

# Extract hook event name: "hook_event_name":"..."
HOOK_EVENT=$(printf '%s' "$FLAT" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# If the event is not one we handle, pass through.
case "$HOOK_EVENT" in
  PreToolUse|UserPromptSubmit) ;;
  *)
    printf '{}'
    exit 0
    ;;
esac

# Resolve BARE_NAME (the unqualified command name, e.g. "build") from
# whichever input shape applies to the current event.
BARE_NAME=""

if [ "$HOOK_EVENT" = "PreToolUse" ]; then
  # Expect tool_input.skill = "AmphiLoop:command".
  #
  # The PreToolUse hook in hooks.json already gates with
  #   "if": "Skill(AmphiLoop:*)"
  # so the engine filters out other-plugin and bare-name Skill calls before
  # this script ever spawns. The case below is a defensive second layer with
  # the same standard — anything that's not AmphiLoop-prefixed is rejected.
  SKILL_NAME=$(printf '%s' "$FLAT" | sed -n 's/.*"skill"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  case "$SKILL_NAME" in
    "$PLUGIN_NAME":*)
      BARE_NAME="${SKILL_NAME#*:}"
      ;;
    *)
      # Anything else (other plugin, bare name, missing field) — reject.
      printf '{}'
      exit 0
      ;;
  esac
else
  # UserPromptSubmit: scan commands/ and look for a `/command` or
  # `/AmphiLoop:command` token in the `"prompt":"..."` JSON field. We don't
  # fully parse the prompt string — we just require the slash-command form to
  # appear so natural-language prompts mentioning `/build` in passing
  # don't false-positive, AND we require any namespace prefix to be exactly
  # `AmphiLoop:` so `/OtherPlugin:build` is rejected.
  if [ -d "$ROOT/commands" ]; then
    for f in "$ROOT"/commands/*.md; do
      [ -f "$f" ] || continue
      name=$(basename "$f" .md)
      # Pattern A: raw slash command in the prompt string
      #   "prompt":"/name..."  or  "prompt":"/AmphiLoop:name..."
      # Pattern B: Claude Code inline-expanded form
      #   <command-name>/?name</command-name>  or  .../AmphiLoop:name</command-name>
      # The `(AmphiLoop:)?` group accepts ONLY our namespace or none —
      # any other prefix fails the match and the loop continues.
      if printf '%s' "$FLAT" | grep -qE "\"prompt\"[[:space:]]*:[[:space:]]*\"/(${PLUGIN_NAME}:)?${name}([^A-Za-z0-9_-]|\\\\|\")"; then
        BARE_NAME="$name"
        break
      fi
      if printf '%s' "$FLAT" | grep -qE "<command-name>/?(${PLUGIN_NAME}:)?${name}</command-name>"; then
        BARE_NAME="$name"
        break
      fi
    done
  fi
fi

# No command detected — pass through.
if [ -z "$BARE_NAME" ]; then
  printf '{}'
  exit 0
fi

# Confirm BARE_NAME actually matches a command file in this plugin. For the
# PreToolUse branch this guards against unrelated skills from other plugins;
# for the UserPromptSubmit branch the loop above already established this,
# but re-checking keeps the two branches symmetric and cheap.
MATCHED=false
if [ -d "$ROOT/commands" ]; then
  for f in "$ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    if [ "$BARE_NAME" = "$name" ]; then
      MATCHED=true
      break
    fi
  done
fi

if [ "$MATCHED" = false ]; then
  printf '{}'
  exit 0
fi

# JSON-escape path values: backslash first, then double-quote.
# Order matters — escaping `"` first would later double-escape the inserted `\`.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

ROOT_ESC=$(json_escape "$ROOT")
PWD_ESC=$(json_escape "$PWD")

# Emit hookSpecificOutput.additionalContext on stdout. Literal "\n" (backslash
# + n) separates lines inside the JSON string — Claude Code parses them as
# newlines when rendering the additionalContext value back into the context.
# permissionDecision is deliberately omitted so the PreToolUse branch only
# adds context and does not override the permission flow of other hooks.
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"---\\nPLUGIN_ROOT=%s\\nPROJECT_ROOT=%s\\nUse these as path prefixes: {PLUGIN_ROOT}/scripts/..., {PLUGIN_ROOT}/skills/..., {PLUGIN_ROOT}/templates/..., {PROJECT_ROOT}/.bridgic/...\\n---"}}' "$HOOK_EVENT" "$ROOT_ESC" "$PWD_ESC"
exit 0
