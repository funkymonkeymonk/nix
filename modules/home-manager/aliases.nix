{config, ...}: let
  cfg = config.myConfig.onepassword or {};
in {
  home.shellAliases = {
    ops =
      if cfg.enable or false
      then "op signin"
      else "";
    oc = "opencode";
    kk = "opencode run";

    jjn = "jj new";
    jjnm = "jj new main";
    jjf = "jj git fetch";
    jjl = "jj log";
    jjd = "jj diff";
    jjs = "jj show";
    jja = "jj absorb";
    jjst = "jj status";
    jjbl = "jj bookmark list";
    jjci = "jj commit";
    jjr = "jj rebase -o";
    jjwa = "jj workspace add";
    jjwl = "jj workspace list";
    jjwf = "jj workspace list --no-pager 2>/dev/null | tail -n +3 | awk '{print $2}' | while read -r path; do [ -d \"$path\" ] || echo \"$path\"; done | xargs -r jj workspace forget";

    dtr = "devenv tasks run";
    dtl = "devenv tasks list";
  };
}
