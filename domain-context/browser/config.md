# Browser Domain — Pipeline Configuration

Additional Phase 2 configuration questions for the browser domain. Ask after the generic Project Mode / LLM questions, using `AskUserQuestion`.

## Browser Environment Mode

Present the options as:

> Choose browser environment:
>
> **1. Default** — Shared browser state across phases (login sessions carry over).
>
> **2. Isolated** — Each phase gets a clean browser profile, auto-cleaned after use. Ensures reproducible runs.
>
> Enter **1** or **2** (default: 1):

Record the chosen **browser mode** — it must be forwarded to Phases 4, 5, and 6 as part of the auxiliary context passed to each sub-agent. Specifically:

- **Isolated mode** → pass `user-data-dir = {PROJECT_ROOT}/.bridgic/browser/` to every sub-agent that launches a browser.
- **Default mode** → omit `user-data-dir`; the browser uses its default profile and shared state.

Do **not** perform a final summary confirmation here — the caller (Phase 2b in `commands/build.md`) owns the single end-of-Phase-2 summary and will include `browser mode` in it.
