# Browser Domain — Verification Context

The generated project drives the browser through the `bridgic-browser` CLI invoked by the `bash` built-in tool. Browser configuration lives in `main.py`'s `BRIDGIC_BROWSER_JSON` env-var setup (`os.environ["BRIDGIC_BROWSER_JSON"] = json.dumps({...})`), not in any `Browser(...)` constructor call.

## Cross-check `on_workflow` against the exploration report

Treat the report's "Operation Sequence" as the source of truth. Any numbered step (or sub-step) missing from `on_workflow` is a bug — fix it, do not work around it.

## Launch-parameter parity (Default mode)

If **browser mode = Default**, verify that the `BRIDGIC_BROWSER_JSON` JSON dict in `main.py` mirrors the launch parameters recorded in the exploration report — `headless`, `viewport`, `channel`, `args`, etc. Mismatches under Default mode break shared-state assumptions (the runtime browser may not see the cookies / login session captured during exploration) and must be fixed before declaring success.

```bash
grep -nE 'BRIDGIC_BROWSER_JSON|"headless"|"viewport"|"channel"' {generator_project}/main.py
```

## Isolated-mode `user_data_dir` override

If **browser mode = Isolated**, the auxiliary context will include `user_data_dir = <PROJECT_ROOT>/.bridgic/browser`. The agent must:

1. **Verify** that the `BRIDGIC_BROWSER_JSON` JSON dict pins `"user_data_dir"` to this exact path (resolve `<PROJECT_ROOT>` before comparing) so verification runs in the same isolated profile chain.
2. After verification is complete and `main.py`'s `finally` has released the persistent CLI browser process (`uv run bridgic-browser close`), **delete the entire `<PROJECT_ROOT>/.bridgic/browser/` directory** to leave a clean state.
