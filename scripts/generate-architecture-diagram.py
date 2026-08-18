#!/usr/bin/env python3
"""
Generate a Mermaid module dependency diagram for docs/explanation/architecture.md.

Parses the REAL `imports = [ ... ]` lists in modules/default.nix and
modules/roles/default.nix (static Nix list literals, one path per line),
plus the conditional role -> home-manager module mapping hand-transcribed
from modules/common/users.nix's `optional config.myConfig.<x>.enable`
chain (that part is a runtime-conditional Nix expression, not a static
list, so it can't be grep-extracted the same way -- see MANUAL_HM_EDGES
below, which is verified against the real file by check_manual_edges()).

This is intentionally a lightweight, dependency-free script (stdlib only)
rather than a full Nix parser: it captures the two things worth showing
in an explanation doc (the static core-module tree, and the role-gated
home-manager module mapping) without pretending to be a complete,
general-purpose Nix import graph tool.

Usage:
    python3 scripts/generate-architecture-diagram.py

Outputs a Mermaid flowchart to stdout. Wire the output into
docs/explanation/architecture.md by hand (between the
<!-- ARCHITECTURE-DIAGRAM:START --> / END markers), or pipe through
`devenv tasks run docs:diagram` (TODO: not yet wired as a task -- see
the yak backlog for scripts/docs-update.sh's generate_* functions,
which have a history of silently going stale; this script is kept
separate and manually invoked for now rather than auto-run on every
docs:generate, precisely to avoid that failure mode).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MODULES_DIR = REPO_ROOT / "modules"

# Role -> home-manager module edges, as conditionally wired in
# modules/common/users.nix's `imports = [...] ++ optional cfg.enable path ++ ...`
# chain. This is a runtime-conditional expression (not a static list), so
# it's hand-transcribed here rather than grep-extracted. check_manual_edges()
# verifies each `myConfig.<option>` string below still appears in
# users.nix, so this list can't silently go stale without at least a
# script failure flagging it.
MANUAL_HM_EDGES = [
    ("myConfig.charm.enable", "home-manager/charm.nix"),
    ("myConfig.opencode.enable", "home-manager/opencode.nix"),
    ("myConfig.claude-code.enable", "home-manager/claude-code.nix"),
    ("myConfig.pi.enable", "home-manager/pi-coding-agent.nix"),
    ("myConfig.vane.openaiBaseUrlOpnixItem", "home-manager/vane-secrets.nix"),
    ("myConfig.zellij.enable", "home-manager/zellij.nix"),
    ("myConfig.agent-skills.enable", "home-manager/skills/install.nix"),
    ("myConfig.email-agent.enable", "home-manager/email-agent.nix"),
    ("myConfig.email-backup.enable", "home-manager/email-backup.nix"),
    ("myConfig.sketchybar.enable", "home-manager/sketchybar"),
    ("myConfig.roles.developer.enable", "home-manager/watch-ci-jobs.nix"),
]

# Modules always imported unconditionally (not role-gated) in users.nix.
ALWAYS_ON_HM_MODULES = [
    "home-manager/themes.nix",
    "home-manager/shell.nix",
    "home-manager/foundation.nix",
]

IMPORT_LINE_RE = re.compile(r"^\s*(\.\/[a-zA-Z0-9_./-]+)\s*$")


def parse_static_imports(nix_file: Path) -> list[str]:
    """Extract `./relative/path` entries from a static `imports = [ ... ];` list."""
    text = nix_file.read_text()
    match = re.search(r"imports\s*=\s*\[(.*?)\]", text, re.DOTALL)
    if not match:
        return []
    body = match.group(1)
    paths = []
    for line in body.splitlines():
        m = IMPORT_LINE_RE.match(line)
        if m:
            paths.append(m.group(1))
    return paths


def check_manual_edges(users_nix: Path) -> list[str]:
    """Verify each MANUAL_HM_EDGES option string still appears in users.nix.

    Returns a list of stale entries (option strings no longer found), so
    the caller can fail loudly instead of silently rendering a diagram
    that no longer matches reality.
    """
    text = users_nix.read_text()
    stale = []
    for option, _module in MANUAL_HM_EDGES:
        if option not in text:
            stale.append(option)
    return stale


def clean_label(path: str) -> str:
    """Turn a Nix import path into a short Mermaid node label."""
    name = path.lstrip("./")
    return name


def sanitize_id(path: str) -> str:
    """Turn a path into a Mermaid-safe node id."""
    return re.sub(r"[^a-zA-Z0-9]", "_", path)


def main() -> int:
    default_nix = MODULES_DIR / "default.nix"
    roles_default_nix = MODULES_DIR / "roles" / "default.nix"
    users_nix = MODULES_DIR / "common" / "users.nix"

    for f in (default_nix, roles_default_nix, users_nix):
        if not f.exists():
            print(f"error: expected file not found: {f}", file=sys.stderr)
            return 1

    stale = check_manual_edges(users_nix)
    if stale:
        print(
            "error: MANUAL_HM_EDGES references options no longer found in "
            f"{users_nix.relative_to(REPO_ROOT)}: {stale}\n"
            "Update MANUAL_HM_EDGES in this script to match the current "
            "conditional imports chain before regenerating the diagram.",
            file=sys.stderr,
        )
        return 1

    core_imports = parse_static_imports(default_nix)
    role_imports = parse_static_imports(roles_default_nix)

    lines = ["flowchart TD"]
    lines.append('    modules["modules/default.nix"]')

    for imp in core_imports:
        if imp in ("./home-manager", "./roles"):
            continue
        node_id = sanitize_id(imp)
        lines.append(f'    {node_id}["{clean_label(imp)}"]')
        lines.append(f"    modules --> {node_id}")

    lines.append('    hm["home-manager/ (shared settings)"]')
    lines.append("    modules --> hm")
    lines.append('    roles["roles/ (modules/roles/default.nix)"]')
    lines.append("    modules --> roles")

    for imp in role_imports:
        node_id = sanitize_id("roles/" + imp.lstrip("./"))
        lines.append(f'    {node_id}["roles/{clean_label(imp)}"]')
        lines.append(f"    roles --> {node_id}")

    lines.append(
        '    usersnix["common/users.nix\\n(role-gated home-manager imports)"]'
    )
    lines.append("    roles -.-> usersnix")

    for always_on in ALWAYS_ON_HM_MODULES:
        node_id = sanitize_id(always_on)
        lines.append(f'    {node_id}["{always_on}\\n(always on)"]')
        lines.append(f"    usersnix --> {node_id}")

    for option, module in MANUAL_HM_EDGES:
        node_id = sanitize_id(module)
        lines.append(f'    {node_id}["{module}"]')
        lines.append(f'    usersnix -->|"{option}"| {node_id}')

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
