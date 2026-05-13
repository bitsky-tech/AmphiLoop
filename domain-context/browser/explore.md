# Browser Domain — Exploration Context

Browser exploration drives the `bridgic-browser` CLI directly. State-mutating actions are wrapped by `browser-observe.sh` to capture action + post-state in one turn; observation (`snapshot`, `tabs`) and lifecycle (`close`) commands run via `uv run bridgic-browser <cmd>` directly.

## Domain reference files

- `{PLUGIN_ROOT}/skills/bridgic-browser/SKILL.md` — browser skill definitions and usage.

## Setup protocol

Install the `bridgic-browser` CLI tool into PROJECT_ROOT's shared uv env:

```bash
bash {PLUGIN_ROOT}/skills/bridgic-browser/scripts/install-deps.sh {PROJECT_ROOT}
```

## Browser configuration (pre-config once)

Pre-configure all launch parameters **before the first `bridgic-browser open` / `search`** by writing `{PROJECT_ROOT}/.bridgic/bridgic-browser.json`, then load it via the `BRIDGIC_BROWSER_JSON` env var on that first command (daemon startup). The daemon persists across CLI invocations, so every subsequent action talks to the already-configured daemon and runs clean — no `--headed`, no `--clear-user-data`, just `bridgic-browser open https://...`.

The auxiliary context includes a **browser mode** (`Default` or `Isolated`); merge it with task-specific needs into one JSON:

| Key | Set when | Value |
|---|---|---|
| `headless` | Task needs login or visual debugging | `false` (default: `true`) |
| `user_data_dir` | Browser mode = `Isolated` | `"{PROJECT_ROOT}/.bridgic/browser"` — `mkdir -p` it beforehand. Omit under `Default` (the browser uses its default profile at `~/.bridgic/bridgic-browser/user_data/`). |
| `viewport` | Layout-sensitive task | `{"width": 1280, "height": 720}` (default: `1600x900`) |
| `channel` | Need system Chrome (e.g. Google OAuth) | `"chrome"` |

Write the file once, then start the daemon with the env var on the first command — subsequent commands run clean:

```bash
mkdir -p {PROJECT_ROOT}/.bridgic/browser    # only when Isolated; under Default just `mkdir -p {PROJECT_ROOT}/.bridgic`
cat > {PROJECT_ROOT}/.bridgic/bridgic-browser.json <<'JSON'
{
  "headless": false,
  "user_data_dir": "{PROJECT_ROOT}/.bridgic/browser"
}
JSON

# First command: daemon startup loads the JSON via env var.
BRIDGIC_BROWSER_JSON="$(cat {PROJECT_ROOT}/.bridgic/bridgic-browser.json)" \
  uv run bridgic-browser open https://example.com

# Subsequent commands: clean — they talk to the running daemon.
uv run bridgic-browser snapshot
uv run bridgic-browser click @xxx
```

Record the JSON content verbatim in the report's Domain Guidance section (for documentation). The file itself is the canonical source — it persists into the code phase, and `main.py` reads it at startup to populate the `BRIDGIC_BROWSER_JSON` env var (see `domain-context/browser/code.md` Phase 3).

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

Snapshot output is either inline (minimal) or a file path (substantial — grep or read it). The wrapper output you ingest stays unresolved — substantial pages inlined per turn would blow exploration context. **At artifact-save time**, resolve any `[notice] saved to: <path>` in the snapshot section to the file content so the saved artifact has the full a11y tree inline — same format production `observation` emits (`domain-context/browser/code.md` §2.7).

## Ref classification — STABLE vs VOLATILE

Browser refs are **deterministic per element**: the same DOM element on the same page yields the same ref string across snapshots and runs (until that page navigates or its DOM is mutated). Use this property to classify every ref recorded in the operation sequence.

| Class | Ref behaviour | Typical examples | What to record |
|---|---|---|---|
| **STABLE** | Same element on the same page reload → same ref | Header / sidebar buttons, fixed search/filter controls, pagination Next, persistent dropdowns, top-level tabs | The literal hex ref value, e.g. `# ref=5dc3463e STABLE` |
| **VOLATILE** | Ref regenerates per page load, per row, or per session | List rows, grid cells, items inside a re-fetched feed, dynamically rendered cards, popover/portal items mounted on demand | Tag the **shape**, not the value: `# row refs VOLATILE`. Save the snapshot artifact (per `amphibious-explore.md` §2.4) so future extraction has real text to parse against. |

Decision rule: a ref is STABLE only if you have **observed it twice** — once in the initial snapshot and once after at least one page reload or unrelated state change — and the value matched. If you have not double-checked, default to VOLATILE; over-tagging STABLE causes runtime breakage when the assumption fails.

When recording a STABLE ref, copy the **exact** hex string from the snapshot — do not abbreviate, do not paraphrase, do not try to "name" the element instead. Future executors read this value verbatim.

## Cleanup protocol

After exploration is complete, release all browser processes started by `bridgic-browser`:

```bash
uv run bridgic-browser close
```

Under `Isolated` mode, also remove the user_data_dir created during configuration — each phase starts from a clean state:

```bash
rm -rf {PROJECT_ROOT}/.bridgic/browser
```
