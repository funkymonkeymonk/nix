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
    jjf = "jj git fetch";
    jjl = "jj log";
    jjd = "jj diff";
    jjs = "jj show";
    jja = "jj absorb";
    jjst = "jj status";
    jjco = "jj comment";
  };
}
