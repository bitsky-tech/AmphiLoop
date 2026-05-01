import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

export default definePluginEntry({
  id: "amphiloop",
  register: () => {
    // No-op: AmphiLoop's behavior is entirely in the bundled skill at
    // extensions/openclaw-skill/amphiloop-build/SKILL.md. This entry exists only
    // so OpenClaw classifies AmphiLoop as a native plugin (via package.json's
    // openclaw.extensions) instead of falling through to Claude Code bundle
    // detection from .claude-plugin/plugin.json.
  },
});
