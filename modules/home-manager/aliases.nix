{
  _config,
  _lib,
  _pkgs,
  ...
}: {
  # Shell aliases configuration
  # This module contains user-specific shell aliases

  home.shellAliases = {
    # Git aliases
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
    gmm = "git fetch origin && git git merge origin/main";
    gf = "git fetch --prune";
    gr = "git restore --source";
    grh = "git reset --hard";
    ghv = "gh repo view --web";

    # Task runner
    t = "task";
    tb = "task build";
    tt = "task test";

    # Navigation
    "..." = "cd ../..";

    # Docker
    dip = "docker inspect --format '{{ .NetworkSettings.IPAddress }}'";
    dkd = "docker run -d -P";
    dki = "docker run -t -i -P";

    # Development
    try = "nix-shell -p";
    ops = "op signin";
  };
}
