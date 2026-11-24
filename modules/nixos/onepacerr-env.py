"""Render OnePacerr's Jellyfin credentials into a restricted runtime env file."""

from __future__ import annotations

import argparse
import os
import pathlib
import sys
import tempfile


def read_secret(path: pathlib.Path) -> str:
    """Read one UTF-8 secret, tolerating one trailing newline from secret tools."""
    try:
        value = path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise ValueError("A configured Jellyfin credential file is unavailable or invalid") from error

    if value.endswith("\n"):
        value = value[:-1]
        if value.endswith("\r"):
            value = value[:-1]

    if not value or any(character in value for character in ("\r", "\n", "\0")):
        raise ValueError("A configured Jellyfin credential is empty or cannot be represented in an env file")
    return value


def render_env(username: str, password: str, output: pathlib.Path) -> None:
    """Atomically write credentials with owner-only permissions and no stdout."""
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(output.parent, 0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".onepacerr-", dir=output.parent)
    temporary = pathlib.Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as env_file:
            env_file.write(f"JELLYFIN_USERNAME={username}\n")
            env_file.write(f"JELLYFIN_PASSWORD={password}\n")
            env_file.flush()
            os.fsync(env_file.fileno())
        os.replace(temporary, output)
        os.chmod(output, 0o600)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username-file", required=True, type=pathlib.Path)
    parser.add_argument("--password-file", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)

    try:
        username = read_secret(args.username_file)
        password = read_secret(args.password_file)
        render_env(username, password, args.output)
    except (OSError, ValueError) as error:
        print(f"OnePacerr credential rendering failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
