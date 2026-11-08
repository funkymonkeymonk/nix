{pkgs, ...}: let
  mkCatalogMachine = import ../library/machines/mk-catalog-machine.nix;
  defaultNixosMachine = mkCatalogMachine {kind = "nixos";} {
    system = "x86_64-linux";
    hostname = "test-server";
    modules = [];
  };
  mkUser = _: "test-user";
  defaultDarwinMachine =
    mkCatalogMachine {
      kind = "darwin";
      extraSpecialArgs = {inherit mkUser;};
    } {
      system = "aarch64-darwin";
      hostname = "test-mac";
      modules = [];
    };
  overriddenMachine = mkCatalogMachine {kind = "nixos";} {
    system = "aarch64-linux";
    hostname = "test-arm";
    modules = [];
    overrides.tailscale.enable = false;
    extraSpecialArgs = {inherit mkUser;};
  };
  checkEqual = name: expected: actual:
    if expected == actual
    then ''echo "${name}: OK"''
    else throw "${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";
in {
  catalogMachineConstructor = pkgs.runCommand "test-machine-catalog-constructor" {} ''
    echo "=== Testing standard machine catalog defaults ==="
    ${checkEqual "NixOS kind" "nixos" defaultNixosMachine.kind}
    ${checkEqual "standard builder" "mk-system" defaultNixosMachine.builder}
    ${checkEqual "empty special args default" {} defaultNixosMachine.extraSpecialArgs}
    ${checkEqual "empty overrides default" {} defaultNixosMachine.overrides}
    ${checkEqual "Darwin special args retain mkUser as a function" true (builtins.isFunction defaultDarwinMachine.extraSpecialArgs.mkUser)}
    ${checkEqual "explicit special args retain mkUser as a function" true (builtins.isFunction overriddenMachine.extraSpecialArgs.mkUser)}
    ${checkEqual "explicit overrides are retained" false overriddenMachine.overrides.tailscale.enable}
    touch $out
  '';
}
