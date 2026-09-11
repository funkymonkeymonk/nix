{
  pkgs,
  includeGomuks ? true,
}:
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
  ++ pkgs.lib.optional includeGomuks pkgs.gomuks
  ++ pkgs.lib.optionals (pkgs ? yaks) [pkgs.yaks]
