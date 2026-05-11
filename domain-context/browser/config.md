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

Record the chosen **browser mode** in `build_context.md`'s `domain_config`. Phase 3 (exploration) reads it to decide what to write into `{PROJECT_ROOT}/.bridgic/bridgic-browser.json` — the canonical browser config file Phases 4 (code) and 5 (verify) inherit. The mode determines a single key in that file:

- **Isolated** → `"user_data_dir": "{PROJECT_ROOT}/.bridgic/browser"` is added to the JSON. That directory becomes the project's private browser profile.
- **Default** → `user_data_dir` is omitted from the JSON; the browser uses its persistent default profile at `~/.bridgic/bridgic-browser/user_data/`.

Do **not** perform a final summary confirmation here — the caller (Phase 2 in `commands/build.md`) owns the single end-of-Phase-2 summary and will include `browser mode` in it.
