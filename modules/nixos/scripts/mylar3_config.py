"""Render declared Mylar3 INI settings into its runtime data directory."""

from __future__ import annotations

import argparse
import configparser
import json
import os
import pathlib
import sys
import tempfile
from typing import Any

from media_api_reconcile import ReconciliationError, expand_runtime_secrets


def render_ini(settings: dict[str, dict[str, Any]], existing: str = "") -> str:
    """Overlay declared settings onto an existing INI document."""
    parser = configparser.ConfigParser(interpolation=None)
    parser.optionxform = str.lower
    if existing:
        parser.read_string(existing)

    expanded = expand_runtime_secrets(settings)
    for section, values in expanded.items():
        if not isinstance(values, dict):
            raise ReconciliationError("Mylar3 settings must be grouped by INI section")
        if not parser.has_section(section):
            parser.add_section(section)
        for key, value in values.items():
            if isinstance(value, (dict, list)) or value is None:
                raise ReconciliationError("Mylar3 setting values must be scalar")
            parser.set(section, key, str(value))

    from io import StringIO

    output = StringIO()
    parser.write(output)
    return output.getvalue()


def write_config(settings_file: str, config_file: str) -> None:
    settings_path = pathlib.Path(settings_file)
    config_path = pathlib.Path(config_file)
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReconciliationError("Unable to read declared Mylar3 settings") from error

    config_path.parent.mkdir(parents=True, exist_ok=True)
    if config_path.is_symlink():
        raise ReconciliationError("Refusing to replace a symlink as the Mylar3 config file")
    try:
        existing = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    except OSError as error:
        raise ReconciliationError("Unable to read the current Mylar3 configuration") from error

    rendered = render_ini(settings, existing)
    descriptor, temporary_path = tempfile.mkstemp(prefix=".config.ini.", dir=config_path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, config_path)
        os.chmod(config_path, 0o600)
    except OSError as error:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise ReconciliationError("Unable to write the runtime Mylar3 configuration") from error


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--settings", required=True, type=pathlib.Path)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        write_config(str(args.settings), str(args.config))
    except ReconciliationError as error:
        print(f"Mylar3 configuration failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
