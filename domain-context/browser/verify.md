# Browser Domain — Phase 6 Verification Context

## Launch-parameter parity (Default mode)

If **browser mode = Default**, verify that the generated `main.py`'s browser launch parameters (headless, channel, args, viewport, etc.) match those recorded in the exploration report from Phase 4. Mismatches under Default mode break shared-state assumptions (the runtime browser may not see the cookies / login session captured during exploration) and must be fixed before declaring success.

## Isolated-mode `user-data-dir` override

If **browser mode = Isolated**, the auxiliary context will include `user-data-dir = {PROJECT_ROOT}/.bridgic/browser/`. The agent must:

1. **Override** `user_data_dir` in the debug-instrumented code to this exact path so verification runs in the same isolated profile chain.
2. After verification is complete and all resources are cleaned up, **delete the entire `{PROJECT_ROOT}/.bridgic/browser/` directory** to leave a clean state for the next run.

## Cross-check `on_workflow` against the exploration report

Treat the report's "Operation Sequence" as the source of truth. Any numbered step (or sub-step) missing from `on_workflow` is a bug — fix it, do not work around it.
