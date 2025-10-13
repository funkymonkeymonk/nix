{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  packages = [pkgs.git];

  # https://devenv.sh/git-hooks/
  git-hooks.hooks.alejandra.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}
