{pkgs, ...}: let
  devenvSource = builtins.readFile ../devenv.nix;
  devenvYaml = builtins.readFile ../devenv.yaml;
  usesDevenvPackages = pkgs.lib.hasInfix "devenv-packages.nix" devenvSource;
  usesFoundationPackages = pkgs.lib.hasInfix "foundation-packages.nix" devenvSource;
  usesDeveloperPackages = pkgs.lib.hasInfix "developer-packages.nix" devenvSource;
  usesLegacyDevBase = pkgs.lib.hasInfix "library/dev-base.nix" devenvSource;
  hasExplicitSecretspecDisabled = pkgs.lib.hasInfix "secretspec:\n  enable: false" devenvYaml;
in {
  devBaseMigration = pkgs.runCommand "test-dev-base-migration" {} ''
    echo "=== Testing canonical devenv package sources ==="
    ${
      if usesDevenvPackages && !usesFoundationPackages
      then ''echo "  devenv uses its curated package list instead of machine foundation packages: OK"''
      else ''echo "  FAIL: devenv must use devenv-packages.nix without foundation-packages.nix"; exit 1''
    }
    ${
      if usesDeveloperPackages
      then ''echo "  devenv consumes developer-packages.nix: OK"''
      else ''echo "  FAIL: devenv must consume developer-packages.nix"; exit 1''
    }
    ${
      if !usesLegacyDevBase
      then ''echo "  devenv no longer consumes library/dev-base.nix: OK"''
      else ''echo "  FAIL: devenv still consumes library/dev-base.nix"; exit 1''
    }
    ${
      if hasExplicitSecretspecDisabled
      then ''echo "  Secretspec integration remains explicitly disabled: OK"''
      else ''echo "  FAIL: secretspec integration disablement must be explicit"; exit 1''
    }
    touch $out
  '';
}
