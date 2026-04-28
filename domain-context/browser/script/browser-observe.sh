#!/bin/bash
# browser-observe.sh — Run one bridgic-browser action, optionally wait for the
# UI to settle, then capture tabs + snapshot in a single tool result. Bundles
# act-and-observe into one shell call so the explore agent halves its per-
# iteration tool turns.
#
# Usage:
#   bash browser-observe.sh [--wait <seconds>] -- <bridgic-browser-args...>
#   (the '--' separator may be omitted when the first action arg does not
#    start with '-')
#
# Examples:
#   browser-observe.sh --wait 3 -- navigate_to --url https://example.com
#   browser-observe.sh -- click_element_by_ref --ref 5dc3463e
#   browser-observe.sh --wait 0.5 input_text_by_ref --ref a9cca048 --text foo
#
# Refused (call directly with `uv run bridgic-browser <cmd>` instead):
#   snapshot, tabs   already observations — wrapping would self-include
#   close            no useful post-state on a closed browser
#
# Output (plain stdout, three labelled sections):
#   === ACTION ===              wrapped command's stdout
#   === POST-ACTION TABS ===    bridgic-browser tabs
#   === POST-ACTION SNAPSHOT === bridgic-browser snapshot
#
# Exit code mirrors the wrapped action's exit code. Failures in the trailing
# tabs/snapshot print "(... failed)" inline but do not change the exit code,
# so the agent can still read the action result and decide what to do.

set -u

WAIT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait)
            shift
            [[ $# -gt 0 ]] || { echo "browser-observe.sh: --wait requires a value" >&2; exit 64; }
            WAIT="$1"
            shift
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        --*)
            echo "browser-observe.sh: unknown flag '$1' (forgot '--' before bridgic-browser args?)" >&2
            exit 64
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "browser-observe.sh: no bridgic-browser arguments provided" >&2
    exit 64
fi

case "$1" in
    snapshot|tabs|close)
        echo "browser-observe.sh: refusing to wrap '$1' — call 'uv run bridgic-browser $1' directly." >&2
        exit 64
        ;;
esac

echo "=== ACTION ==="
uv run bridgic-browser "$@"
ACTION_EXIT=$?

case "$WAIT" in
    0|0.0|0.00) ;;
    *) sleep "$WAIT" ;;
esac

echo ""
echo "=== POST-ACTION TABS ==="
uv run bridgic-browser tabs || echo "(tabs failed)"

echo ""
echo "=== POST-ACTION SNAPSHOT ==="
uv run bridgic-browser snapshot || echo "(snapshot failed)"

exit $ACTION_EXIT
