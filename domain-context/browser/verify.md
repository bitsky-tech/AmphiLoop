# Browser Domain — Verification Context

The generated project drives the browser through the `bridgic-browser` CLI invoked by the `bash` built-in tool. Browser configuration lives in `<PROJECT_ROOT>/.bridgic/bridgic-browser.json` (written during exploration); `main.py` reads that file at startup and bridges the content into the `BRIDGIC_BROWSER_JSON` env var the daemon picks up.

## Cross-check `on_workflow` against the exploration report

Treat the report's "Operation Sequence" as the source of truth. Any numbered step (or sub-step) missing from `on_workflow` is a bug — fix it, do not work around it.

## Browser-config file presence and bridging

Verify the canonical config file exists at `<PROJECT_ROOT>/.bridgic/bridgic-browser.json`, and that `main.py` reads it into `BRIDGIC_BROWSER_JSON`:

```bash
test -f {PROJECT_ROOT}/.bridgic/bridgic-browser.json && echo OK
grep -nE 'BRIDGIC_BROWSER_JSON.*read_text|read_text.*BRIDGIC_BROWSER_JSON' {generator_project}/main.py
```

If the file is missing, the bridge in `main.py` silently no-ops and the daemon falls back to defaults — verification has to surface this as a setup-incomplete failure, not a runtime mystery.

## Launch-parameter parity (Default mode)

If **browser mode = Default**, verify the file's content mirrors the launch parameters recorded in the exploration report — `headless`, `viewport`, `channel`, `args`, etc.:

```bash
cat {PROJECT_ROOT}/.bridgic/bridgic-browser.json
```

Compare key-by-key against the report's Domain Guidance section. Mismatches under Default mode break shared-state assumptions (the runtime browser may not see the cookies / login session captured during exploration) and must be fixed before declaring success.

## Isolated-mode `user_data_dir` override

If **browser mode = Isolated**, the auxiliary context will include `user_data_dir = <PROJECT_ROOT>/.bridgic/browser`. The agent must:

1. **Verify** that `<PROJECT_ROOT>/.bridgic/bridgic-browser.json` pins `"user_data_dir"` to this exact path (resolve `<PROJECT_ROOT>` before comparing) so verification runs in the same isolated profile chain.
2. After verification is complete and `main.py`'s `finally` has released the persistent CLI browser process (`uv run bridgic-browser close`), **delete the entire `<PROJECT_ROOT>/.bridgic/browser/` directory** to leave a clean state.
