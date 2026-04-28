# Browser Domain — Phase 3 Exploration Context

## Domain reference files to read

- `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` — browser skill definitions and usage.

## Setup protocol

Install the skill into PROJECT_ROOT — the single shared uv env reused by Phase 4:

```bash
bash {PLUGIN_ROOT}/skills/bridgic-browser/scripts/install-deps.sh {PROJECT_ROOT}
```

## Observation protocol

Pick the call form by **command kind**:

| Command | How to invoke |
|---|---|
| State-mutating **CLI action** (`open`, `click`, `wait`, …) | `bash {PLUGIN_ROOT}/domain-context/browser/script/browser-observe.sh [--wait <s>] -- <args...>` — runs the action, waits, then prints `=== ACTION ===` / `=== POST-ACTION TABS ===` / `=== POST-ACTION SNAPSHOT ===`. |
| Observation (`snapshot`, `tabs`) or lifecycle (`close`) | `uv run bridgic-browser <cmd>` **directly**. |

`--wait`: navigation / content-loading click **3–5s**; dropdown / text input **1–2s**; otherwise omit.

**Hard rules:**

1. **The wrapper REFUSES `snapshot`, `tabs`, `close`** — they are not actions; wrapping self-includes or runs on a dead browser. `bash browser-observe.sh -- tabs` fails with `refusing to wrap '<cmd>'` and burns a turn. Always call them via `uv run bridgic-browser <cmd>` directly.
2. **Do not re-fetch `snapshot` / `tabs` after each action** — the wrapper already printed both. Re-fetching is the most common waste pattern. Direct calls are reserved for genuinely insufficient wrapper output (snapshot truncated, late render, tab-focus confirmation).

Snapshot output (wrapper or direct) is either inline (minimal) or a file path (substantial — grep or read it).

## Ref classification — STABLE vs VOLATILE

Browser refs are **deterministic per element**: the same DOM element on the same page yields the same ref string across snapshots and runs (until that page navigates or its DOM is mutated). Use this property to classify every ref recorded in the operation sequence — the code agent will hardcode STABLE refs as constants and only write extraction helpers for VOLATILE ones.

| Class | Ref behaviour | Typical examples | What to record |
|---|---|---|---|
| **STABLE** | Same element on the same page reload → same ref | Header / sidebar buttons, fixed search/filter controls, pagination Next, persistent dropdowns, top-level tabs | The literal hex ref value, e.g. `# ref=5dc3463e STABLE` |
| **VOLATILE** | Ref regenerates per page load, per row, or per session | List rows, grid cells, items inside a re-fetched feed, dynamically rendered cards, popover/portal items mounted on demand | Tag the **shape**, not the value: `# row refs VOLATILE`. Save the snapshot artifact (see "Save Key Artifacts" in the framework rules) so the code agent can write a parser against real text. |

Decision rule: a ref is STABLE only if you have **observed it twice** — once in the initial snapshot and once after at least one page reload or unrelated state change — and the value matched. If you have not double-checked, default to VOLATILE; over-tagging STABLE causes runtime breakage when the assumption fails. STABLE is the privileged case (literal value travels into code), VOLATILE is the safe default.

When recording a STABLE ref, copy the **exact** hex string from the snapshot — do not abbreviate, do not paraphrase, do not try to "name" the element instead. The code agent reads this value verbatim.

## Browser launch parameters

Record the **full browser launch parameters** used in this phase (headless, channel, args, viewport, etc., **excluding `user-data-dir`**) into the exploration report. Phase 4 must mirror these values in `main.py` so runtime behavior matches what was observed.

Parameter Setting Guide:
1. If the task requires login, please launch the browser in non-headless mode to facilitate authentication.

## Browser environment mode

The auxiliary context will include a **browser mode** value (`Default` or `Isolated`):

- **Isolated** → use `user-data-dir = {PROJECT_ROOT}/.bridgic/browser/`. Create this directory before launching the browser, and **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** after exploration is complete and resources are cleaned up, so subsequent phases start with a clean browser state.
- **Default** → omit `user-data-dir`; the browser uses its default profile.

## Cleanup protocol

Run once at the end of exploration to release all browser processes started by `bridgic-browser`:

```bash
uv run bridgic-browser close
```
