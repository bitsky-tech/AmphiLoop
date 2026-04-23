# Browser Domain — Phase 4 Exploration Context

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

## Browser launch parameters

Record the **full browser launch parameters** used in this phase (headless, channel, args, viewport, etc., **excluding `user-data-dir`**) into the exploration report. Phase 5 must mirror these values in `main.py` so runtime behavior matches what was observed.

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
