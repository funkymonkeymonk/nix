{
  _config,
  _lib,
  _pkgs,
  ...
}: {
  # Shell aliases configuration
  # This module contains aliases for programs NOT installed in base bundle

  home.shellAliases = {
    # Docker (only available when development role is enabled)
    dip = "docker inspect --format '{{ .NetworkSettings.IPAddress }}'";
    dkd = "docker run -d -P";
    dki = "docker run -t -i -P";

    # Development tools
    try = "nix-shell -p";
    ops = "op signin"; # 1Password CLI (available on NixOS systems)
    oc = "opencode"; # AI assistant (available when developer role is enabled)
  };
}
