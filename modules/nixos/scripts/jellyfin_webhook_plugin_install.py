"""Install the pinned Jellyfin Webhook plugin into its writable data directory."""

from __future__ import annotations

import argparse
import pathlib
import shutil
import stat
import sys


class PluginInstallError(RuntimeError):
    """The requested plugin installation is unsafe or incomplete."""


def install_plugin(source: pathlib.Path, destination: pathlib.Path) -> None:
    """Copy a Nix-store plugin to Jellyfin's writable data directory."""
    try:
        source = pathlib.Path(source).resolve(strict=True)
    except OSError as error:
        raise PluginInstallError("The pinned Jellyfin plugin package is unavailable") from error
    destination = pathlib.Path(destination)
    if not source.is_dir():
        raise PluginInstallError("The pinned Jellyfin plugin package is not a directory")

    if destination.is_symlink():
        try:
            link_target = destination.resolve(strict=True)
        except OSError as error:
            raise PluginInstallError("The existing Jellyfin plugin symlink is broken") from error
        if link_target != source:
            raise PluginInstallError("The existing Jellyfin plugin symlink is not Nix-managed")
        destination.unlink()
    elif destination.exists() and not destination.is_dir():
        raise PluginInstallError("The Jellyfin plugin destination is not a directory")

    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, destination, symlinks=True)

    for path in (destination, *destination.rglob("*")):
        if path.is_symlink():
            continue
        mode = stat.S_IMODE(path.stat().st_mode) | stat.S_IWUSR
        if path.is_dir():
            mode |= stat.S_IXUSR
        path.chmod(mode)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--destination", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        install_plugin(args.source, args.destination)
    except (OSError, PluginInstallError) as error:
        print(f"Jellyfin Webhook plugin installation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
