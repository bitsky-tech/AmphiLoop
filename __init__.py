"""amphi-loop — Hermes plugin entry point.

Registers the AmphiLoop skill corpus (build orchestrator + 4 amphibious
methodology docs + 3 bridgic skill mirrors) and the ``/amphi-build``
slash command.

All skills are namespaced as ``amphi-loop:<name>`` and loaded explicitly
via ``skill_view`` (not surfaced in the default ``<available_skills>``
index).  ``/amphi-build`` injects the build skill's full content as a
user-message activation, with the on-disk plugin root substituted for
``skill_dir`` so the agent can resolve every bundled resource (templates,
scripts, domain-context, sub-skill methodology files).
"""

from __future__ import annotations

import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

PLUGIN_NAME = "amphi-loop"
BUILD_SKILL = f"{PLUGIN_NAME}:build"

_FRONTMATTER_DESC_RE = re.compile(
    r'^description:\s*"?(.+?)"?\s*$', re.MULTILINE
)


def _extract_description(md_path: Path) -> str:
    """Pull the ``description:`` field from a YAML frontmatter block."""
    try:
        text = md_path.read_text(encoding="utf-8")
    except OSError:
        return ""
    match = _FRONTMATTER_DESC_RE.search(text)
    return match.group(1).strip() if match else ""


def _discover_skills(plugin_root: Path) -> dict[str, Path]:
    """Map each registered skill name to its `.md` file path.

    AmphiLoop-01 keeps its content in three sibling directories:
    - ``skills/<name>/SKILL.md``  → the bridgic-* knowledge skills
    - ``agents/<name>.md``         → the 4 amphibious-* methodology docs
    - ``commands/<name>.md``       → the build orchestrator
    """
    skills: dict[str, Path] = {}

    skills_dir = plugin_root / "skills"
    if skills_dir.is_dir():
        for child in sorted(skills_dir.iterdir()):
            skill_md = child / "SKILL.md"
            if child.is_dir() and skill_md.is_file():
                skills[child.name] = skill_md

    for subdir_name in ("agents", "commands"):
        subdir = plugin_root / subdir_name
        if subdir.is_dir():
            for md in sorted(subdir.glob("*.md")):
                skills[md.stem] = md

    return skills


def _make_build_handler(ctx, plugin_root: Path):
    """Slash-command handler for ``/amphi-build`` — fires the build pipeline."""

    def _handle_build(raw_args: str) -> str:
        task = (raw_args or "").strip()

        try:
            from agent.skill_commands import (
                _build_skill_message,
                _load_skill_payload,
            )
        except Exception:
            _build_skill_message = None
            _load_skill_payload = None

        # Pass the AmphiLoop-01 ROOT as skill_dir (not commands/) so
        # _build_skill_message auto-lists supporting files from
        # templates/, scripts/, etc. — every path build.md references.
        # Plugin-namespaced skills come back from skill_view() with
        # skill_dir=None, so the substitution is mandatory: without it,
        # Phase 0a has no `[Skill directory: /…]` anchor to bind from.
        anchor_dir = plugin_root

        message: str | None = None
        if _load_skill_payload and _build_skill_message:
            loaded = _load_skill_payload(BUILD_SKILL)
            if loaded:
                loaded_skill, _ignored_dir, skill_name = loaded
                activation_note = (
                    f'[IMPORTANT: The user invoked the "{skill_name}" skill via '
                    f'`/amphi-build`. Follow its instructions on the task below.]'
                )
                message = _build_skill_message(
                    loaded_skill,
                    anchor_dir,
                    activation_note,
                    user_instruction=task,
                )

        if not message:
            message = (
                f"Load the skill `{BUILD_SKILL}` via "
                f'skill_view("{BUILD_SKILL}") and follow its instructions '
                f"for the following task:\n\n{task or '(see TASK.md in the cwd)'}"
            )

        ok = ctx.inject_message(message, role="user")
        if ok:
            return f"⚡ Loading skill: {BUILD_SKILL}"
        return (
            f"Could not inject the build message (no active CLI). "
            f"Run `skill_view {BUILD_SKILL}` manually or open `hermes chat` first."
        )

    return _handle_build


def register(ctx) -> None:
    """Register all AmphiLoop-01 skills + the ``/amphi-build`` command."""
    plugin_root = Path(__file__).parent

    skills = _discover_skills(plugin_root)
    if not skills:
        logger.warning("%s: no skill files found under %s", PLUGIN_NAME, plugin_root)
        return

    for name, md_path in skills.items():
        description = _extract_description(md_path)
        ctx.register_skill(name, md_path, description=description)

    ctx.register_command(
        "amphi-build",
        handler=_make_build_handler(ctx, plugin_root),
        description="Run the AmphiLoop build pipeline (amphi-loop:build) on a task. Optional --<domain> flag.",
        args_hint="[--<domain>] <task description>",
    )

    logger.debug(
        "%s: registered %d skills (%s) + /amphi-build",
        PLUGIN_NAME,
        len(skills),
        ", ".join(sorted(skills)),
    )
