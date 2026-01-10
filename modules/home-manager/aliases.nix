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
    gkk = "opencode run \"Review all changes, stage them, generate an appropriate commit message, and commit and push the changes\""; # AI-assisted git workflow: review, stage, commit message generation, commit, and push
    gpr = "opencode run \"Check if there's already an open pull request for this branch. If there is, update it with the latest changes. If not, analyze all changes since diverging from the main branch and create a new pull request with an appropriate title and body\""; # AI-assisted pull request creation/update with analysis and PR generation
  };
}
