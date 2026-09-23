{
  pkgs,
  includeGomuks ? true,
}: let
  gomuks = builtins.tryEval pkgs.gomuks;
in
  with pkgs;
    [
      clang
      python3
      nodejs
      yarn
      k3d
      kubectl
      kubernetes-helm
      k9s
      gh-dash
      slidev-cli
      temporal-cli
      mergiraf
    ]
    ++ pkgs.lib.optionals (includeGomuks && gomuks.success) [gomuks.value]
    ++ pkgs.lib.optionals (pkgs ? yaks) [pkgs.yaks]
