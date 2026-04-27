# Browser Domain — Phase 3 Exploration Context

## Domain reference files to read

- `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` — browser skill definitions and usage.

## Observation protocol

Run both commands together before every action to capture the current environment state:

```bash
uv run bridgic-browser snapshot       # current tab's page state
uv run bridgic-browser tabs           # all open tabs + which is active
```

- Use `tabs` to track open tabs and identify the active tab so subsequent actions target the correct page context.
- `snapshot` has two output modes (the CLI decides automatically):
  - **Minimal content** — the full snapshot is printed to stdout; locate target elements directly in the terminal output.
  - **Substantial content** — only a file path is printed; search for task-related keywords in that file, or read it in full to find the target elements and their refs.

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
