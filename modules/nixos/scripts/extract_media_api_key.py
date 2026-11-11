"""Materialize a local media service API key in a restricted runtime file."""

from __future__ import annotations

import argparse
import os
import pathlib
import sys
import tempfile
import time
import xml.etree.ElementTree as ElementTree
from typing import Any

import yaml


def find_api_key(value: Any) -> str | None:
    if not isinstance(value, dict):
        return None
    for key, child in value.items():
        if str(key).casefold() == "apikey" and isinstance(child, (str, int)):
            return str(child).strip() or None
    for child in value.values():
        result = find_api_key(child)
        if result:
            return result
    return None


def extract_key(file_format: str, source: pathlib.Path) -> str:
    try:
        if file_format == "xml":
            root = ElementTree.parse(source).getroot()
            value = next(
                (item.text for item in root.iter() if item.tag.casefold() == "apikey" and item.text),
                None,
            )
        else:
            document = yaml.safe_load(source.read_text(encoding="utf-8"))
            auth = document.get("auth", {}) if isinstance(document, dict) else {}
            value = find_api_key(auth)
    except (OSError, ElementTree.ParseError, yaml.YAMLError) as error:
        raise RuntimeError("Unable to read the media application API-key configuration") from error
    if not value or not str(value).strip():
        raise RuntimeError("The media application API key is not configured")
    return str(value).strip()


def wait_for_key(file_format: str, source: pathlib.Path, timeout_seconds: int = 90) -> str:
    deadline = time.monotonic() + timeout_seconds
    last_error: RuntimeError | None = None
    while time.monotonic() < deadline:
        try:
            return extract_key(file_format, source)
        except RuntimeError as error:
            last_error = error
            time.sleep(1)
    raise RuntimeError("Media application API key did not become available before timeout") from last_error


def write_key(output: pathlib.Path, api_key: str) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".api-key.", dir=output.parent)
    try:
        os.fchmod(descriptor, 0o640)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(api_key)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
        os.chmod(output, 0o640)
    except OSError:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=["xml", "yaml"], required=True)
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        write_key(args.output, wait_for_key(args.format, args.source))
    except (OSError, RuntimeError) as error:
        print(f"Media API-key extraction failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
