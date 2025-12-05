{
  # Base shell aliases for programs installed in base bundle
  # These aliases are available system-wide since base programs are always installed

  environment.shellAliases = {
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
    gmm = "git fetch origin && git merge origin/main";
    gf = "git fetch --prune";
    gr = "git restore --source";
    grh = "git reset --hard";
    ghv = "gh repo view --web";

    # Task runner
    t = "task";
    tb = "task build";
    tt = "task test";

    # Jujutsu (jj) version control aliases
    j = "jj";
    js = "jj status";
    jd = "jj diff";
    ja = "jj abandon";
    jc = "jj commit";
    jl = "jj log";
    jn = "jj new";
    je = "jj edit";
    jg = "jj git";

    # Navigation
    "..." = "cd ../..";
  };
}
