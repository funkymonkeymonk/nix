{
  pkgs,
  self,
  inputs,
  ...
}: let
  lib = pkgs.lib;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  projectMachineModules = import ../library/machines/modules.nix {inherit inputs;};
  catalogNixos = lib.filterAttrs (_: machine: machine.kind == "nixos") catalog;
  catalogDarwin = lib.filterAttrs (_: machine: machine.kind == "darwin") catalog;
  catalogNames = builtins.attrNames catalog;
  catalogNixosNames = builtins.attrNames catalogNixos;
  catalogDarwinNames = builtins.attrNames catalogDarwin;
  nativeNixosNames = builtins.attrNames self.nixosConfigurations;
  nativeDarwinNames = builtins.attrNames self.darwinConfigurations;
  rootDevenv = import ../devenv.nix {inherit pkgs inputs;};
  machineModules = builtins.filter (module: builtins.isAttrs module && builtins.hasAttr "machines" module) rootDevenv.imports;
  machinesProjection = builtins.head machineModules;
  machinesNames = builtins.attrNames machinesProjection.machines;
  syntheticSpecialArgs = {
    inputs.synthetic = "constructor-input";
    mkUser = name: "user-${name}";
  };
  nestedArgumentModule = {
    inputs,
    mkUser,
    ...
  }: {
    config.nestedValue = "${inputs.synthetic}:${mkUser "nested"}";
  };
  rootArgumentModule = {
    inputs,
    mkUser,
    ...
  }: {
    imports = [nestedArgumentModule];
    config.rootValue = "${inputs.synthetic}:${mkUser "root"}";
  };
  argumentOptions = {lib, ...}: {
    options.rootValue = lib.mkOption {type = lib.types.str;};
    options.nestedValue = lib.mkOption {type = lib.types.str;};
  };
  withSpecialArgs = import ../library/machines/with-special-args.nix {inherit lib;};
  argumentEvaluation = lib.evalModules {
    modules = [
      (withSpecialArgs syntheticSpecialArgs rootArgumentModule)
      argumentOptions
    ];
  };
  representativeNixos = catalog.zero;
  representativeDarwin = catalog.wweaver;
  nativeZeroModules = projectMachineModules {
    machine = representativeNixos;
    includeDisko = true;
  };
  devenvZeroModules = projectMachineModules {machine = representativeNixos;};
  explicitDiskoModules = modules: builtins.filter (module: module == inputs.disko.nixosModules.disko) modules;
  projectedZero = machinesProjection.machines.zero.nixos;
  projectedBootstrap = machinesProjection.machines.bootstrap.nixos;
  projectedInstallerIso = machinesProjection.machines.installer-iso.nixos;
  projectedWweaver = machinesProjection.machines.wweaver."nix-darwin";
  projectedMegamanX = machinesProjection.machines.MegamanX."nix-darwin";
  devenvMegamanX = inputs.nix-darwin.lib.darwinSystem {
    system = machinesProjection.machines.MegamanX.system;
    specialArgs = {inherit inputs self;};
    modules = [projectedMegamanX];
  };
  machinesZero = inputs.nixpkgs.lib.nixosSystem {
    inherit (representativeNixos) system;
    specialArgs = {inherit inputs self;};
    # devenv 2.4 imports the disko module before each Machines NixOS module.
    modules = [inputs.disko.nixosModules.disko projectedZero];
  };
  machinesBootstrap = inputs.nixpkgs.lib.nixosSystem {
    inherit (catalog.bootstrap) system;
    specialArgs = {inherit inputs self;};
    modules = [projectedBootstrap];
  };
  machinesInstallerIso = inputs.nixpkgs.lib.nixosSystem {
    inherit (catalog.installer-iso) system;
    specialArgs = {inherit inputs self;};
    modules = [projectedInstallerIso];
  };
  nixosConstructorArgs = inputs // {inherit inputs;} // representativeNixos.extraSpecialArgs;
  darwinConstructorArgs = {inherit inputs;} // representativeDarwin.extraSpecialArgs;
  assertEqual = name: expected: actual:
    if expected == actual
    then ''echo "${name}: OK"''
    else throw "${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";
  test = pkgs.runCommand "test-machines-inventory" {} ''
    echo "=== Testing canonical machine inventory projections ==="
    ${assertEqual "root module receives constructor args" "constructor-input:user-root" argumentEvaluation.config.rootValue}
    ${assertEqual "nested import receives constructor args" "constructor-input:user-nested" argumentEvaluation.config.nestedValue}
    ${assertEqual "NixOS catalog/native names" catalogNixosNames nativeNixosNames}
    ${assertEqual "Darwin catalog/native names" catalogDarwinNames nativeDarwinNames}
    ${assertEqual "root devenv imports one Machines projection" 1 (builtins.length machineModules)}
    ${assertEqual "Catalog/Machines names" catalogNames machinesNames}
    ${assertEqual "zero system" "x86_64-linux" representativeNixos.system}
    ${assertEqual "zero hostname" "zero" representativeNixos.hostname}
    ${assertEqual "zero module count" 11 (builtins.length representativeNixos.modules)}
    ${assertEqual "catalog records explicit disko metadata for zero" true (representativeNixos.disko or false)}
    ${assertEqual "native projection explicitly imports disko once" 1 (builtins.length (explicitDiskoModules nativeZeroModules))}
    ${assertEqual "Machines projection omits the catalog disko module" 0 (builtins.length (explicitDiskoModules devenvZeroModules))}
    ${assertEqual "zero auto-upgrade URL" "github:funkymonkeymonk/nix#zero" representativeNixos.overrides.autoUpgrade.flakeUrl}
    ${assertEqual "zero extra special args" ["mkUser"] (builtins.attrNames representativeNixos.extraSpecialArgs)}
    ${assertEqual "zero mkUser special arg is a function" true (builtins.isFunction representativeNixos.extraSpecialArgs.mkUser)}
    ${assertEqual "zero target module retained" true (builtins.elem ../targets/zero representativeNixos.modules)}
    ${assertEqual "generated zero hostname" "zero" self.nixosConfigurations.zero.config.networking.hostName}
    ${assertEqual "generated zero system" "x86_64-linux" self.nixosConfigurations.zero.config.nixpkgs.hostPlatform.system}
    ${assertEqual "generated zero override" "github:funkymonkeymonk/nix#zero" self.nixosConfigurations.zero.config.myConfig.autoUpgrade.flakeUrl}
    ${assertEqual "native zero retains configured disko devices" true (builtins.attrNames self.nixosConfigurations.zero.config.disko.devices != [])}
    ${assertEqual "Machines zero system" "x86_64-linux" machinesProjection.machines.zero.system}
    ${assertEqual "Machines zero NixOS role" true (builtins.hasAttr "nixos" machinesProjection.machines.zero)}
    ${assertEqual "Machines zero evaluates its NixOS module stack" "zero" machinesZero.config.networking.hostName}
    ${assertEqual "Machines zero has disko devices from the automatic module" true (builtins.attrNames machinesZero.config.disko.devices != [])}
    ${assertEqual "Machines bootstrap evaluates its NixOS module stack" "nixos-bootstrap" machinesBootstrap.config.networking.hostName}
    ${assertEqual "Machines installer ISO evaluates its NixOS module stack" "nixos-installer" machinesInstallerIso.config.networking.hostName}
    ${assertEqual "zero projection retains NixOS constructor arguments" (builtins.attrNames nixosConstructorArgs) (builtins.attrNames (projectedZero.config._module.args or {}))}
    ${assertEqual "zero projection supplies root nixpkgs input" inputs.nixpkgs.outPath projectedZero.config._module.args.nixpkgs.outPath}
    ${assertEqual "zero projection supplies inputs set" inputs.nixpkgs.outPath projectedZero.config._module.args.inputs.nixpkgs.outPath}
    ${assertEqual "zero projection supplies mkUser" true (builtins.isFunction projectedZero.config._module.args.mkUser)}
    ${assertEqual "zero projection wraps module paths" true (builtins.isFunction (builtins.elemAt projectedZero.imports 6))}
    ${assertEqual "bootstrap projection retains raw constructor arguments" [] (builtins.attrNames (projectedBootstrap.config._module.args or {}))}
    ${assertEqual "bootstrap projection wraps module paths" true (builtins.isFunction (builtins.head projectedBootstrap.imports))}
    ${assertEqual "installer ISO projection retains inputs argument" ["inputs"] (builtins.attrNames (projectedInstallerIso.config._module.args or {}))}
    ${assertEqual "installer ISO projection supplies inputs set" inputs.nixpkgs.outPath projectedInstallerIso.config._module.args.inputs.nixpkgs.outPath}
    ${assertEqual "installer ISO projection wraps module paths" true (builtins.isFunction (builtins.head projectedInstallerIso.imports))}
    ${assertEqual "wweaver system" "aarch64-darwin" representativeDarwin.system}
    ${assertEqual "wweaver hostname" "wweaver" representativeDarwin.hostname}
    ${assertEqual "wweaver module count" 4 (builtins.length representativeDarwin.modules)}
    ${assertEqual "wweaver extra special args" ["mkUser"] (builtins.attrNames representativeDarwin.extraSpecialArgs)}
    ${assertEqual "Machines wweaver system" "aarch64-darwin" machinesProjection.machines.wweaver.system}
    ${assertEqual "Machines wweaver nix-darwin role" true (builtins.hasAttr "nix-darwin" machinesProjection.machines.wweaver)}
    ${assertEqual "MegamanX Machines evaluates a nix-darwin build derivation" true (builtins.isString devenvMegamanX.config.system.build.toplevel.drvPath)}
    ${assertEqual "wweaver projection retains Darwin constructor arguments" (builtins.attrNames darwinConstructorArgs) (builtins.attrNames (projectedWweaver.config._module.args or {}))}
    ${assertEqual "wweaver projection supplies inputs set" inputs.nixpkgs.outPath projectedWweaver.config._module.args.inputs.nixpkgs.outPath}
    ${assertEqual "wweaver projection supplies mkUser" true (builtins.isFunction projectedWweaver.config._module.args.mkUser)}
    ${assertEqual "wweaver projection wraps module paths" true (builtins.isFunction (builtins.elemAt projectedWweaver.imports 3))}
    echo "All machine inventory projection tests passed"
    touch $out
  '';
in {
  machinesInventory = test;
}
