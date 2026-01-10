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
    kk = "opencode run"; # AI assistant run command
    gkk = "git status && git diff --staged && git add -A && MSG=$(opencode run \"Generate a concise git commit message for these changes:\" <<< \"$(git diff --staged)\" 2>/dev/null || echo \"Update configuration\") && git commit -m \"$MSG\" && git push"; # Review, AI-generate commit message, commit and push changes
  };
}
