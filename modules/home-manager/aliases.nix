{
  _config,
  _lib,
  _pkgs,
  ...
}: {
  # Shell aliases configuration
  # This module contains aliases for programs NOT installed in base bundle

  home.shellAliases = {
    # Development tools
    try = "nix-shell -p";
    ops =
      if _config.myConfig.onepassword.enable
      then "op signin"
      else ""; # 1Password CLI (conditional)
    oc = "opencode"; # AI assistant (available when developer role is enabled)
    kk = "opencode run"; # AI assistant run command
    gkk = "opencode run \"First check if current branch is default branch (main/master). If it is, create a new appropriately-named branch based on changes before committing. Then review all changes, stage them, generate an appropriate commit message, and commit and push changes\""; # AI-assisted git workflow: creates branch if on default, then review, stage, commit message generation, commit, and push
    gpr = "opencode run \"Check if there's already an open pull request for this branch. If there is, update it with the latest changes. If not, analyze all changes since diverging from main branch and create a new pull request with an appropriate title and body. After PR is created or updated, ask me if I want to open it in browser. Wait for my response. Default to yes if I just press enter. If I say yes or press enter, open PR in my default browser using 'gh pr view --web'.\""; # AI-assisted pull request creation/update with analysis and PR generation
    gpro = "gh pr view --web"; # Open current PR in browser
  };
}
