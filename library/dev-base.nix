# library/dev-base.nix
# Shared developer base configuration.
# Used by both nix-darwin targets (via modules/darwin/dev-base.nix)
# and devenv shells (via devenv.nix).
#
# Contains packages, aliases, env vars, and system defaults that are
# common to all software development environments in this repo.
# No secrets, no machine-specific services, no home-manager config.
{pkgs}:
with pkgs; {
  # Packages installed on every dev machine (Darwin or NixOS)
  packages = [
    # Editor / terminal / file manager
    helix
    zellij
    yazi

    # System monitoring
    htop

    # Git & version control
    gh
    jujutsu
    delta
    gh-dash

    # Search & navigation
    ripgrep
    fd
    fzf
    zoxide
    tree
    eza
    bat
    entr

    # Data processing
    jq
    jnv

    # TUI utilities
    gum

    # Development environment
    devenv
    direnv

    # Nix development tools
    alejandra
    statix
    deadnix
    nix-tree
    nvd
    nixd

    # Containers (Darwin dev workflow)
    docker
    colima
  ];

  # Shell aliases for all dev environments
  shellAliases = {
    # Git shortcuts
    g = "git";
    gst = "git status";
    gpush = "git push";
    gpull = "git pull";
    gd = "git diff";
    gdc = "git diff --cached";
    gco = "git checkout";
    gcob = "git checkout -b";
    gau = "git add -u";
    gauc = "git add -u && git commit -m ";
    gaum = "git add -u && git commit --amend";
    gs = "git stash";
    gsp = "git stash pop";
    gshow = "git stash show -p";
    grm = "git fetch origin && git rebase main";
    grc = "git rebase --continue";
    gm = "git merge";
    gmm = "git fetch origin && git merge origin/main";
    gf = "git fetch --prune";
    gr = "git restore --source";
    grh = "git reset --hard";
    ghv = "gh repo view --web";
    gclean = "git clean -fd";
    gkkb = ''git checkout -b $(date +"%Y%m%d%H%M%S")'';

    # Nix
    try = "nix-shell -p";

    # Navigation
    "..." = "cd ../..";
  };

  # Environment variables
  environmentVariables = {
    EDITOR = "helix";
    VISUAL = "helix";
  };

  # Darwin system defaults shared by all targets
  darwinDefaults = {
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    dock.autohide = true;
  };
}
