{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;

  flakeText = builtins.readFile ../flake.nix;
  outputsText = builtins.readFile ../library/outputs.nix;
  devenvText = builtins.readFile ../devenv.nix;
  devenvYamlPath = ../devenv.yaml;
  devenvYamlExists = builtins.pathExists devenvYamlPath;
  devenvYamlText =
    if devenvYamlExists
    then builtins.readFile devenvYamlPath
    else "";
  machinesProjectionReceivesFacterInput =
    lib.hasInfix "nixos-facter-modules:" devenvYamlText
    && lib.hasInfix "github:nix-community/nixos-facter-modules" devenvYamlText
    && lib.hasInfix "follows: nixpkgs" devenvYamlText
    && lib.hasInfix "import ./library/machines/devenv.nix {inherit inputs;}" devenvText;
  machineBuildInputs = [
    "bifrost"
    "devenv"
    "himalaya-tui"
    "nix-homebrew"
    "nixpkgs-stable"
    "pi-plugins"
    "superpowers"
    "zellij-pane-tracker"
  ];
  machineBuildInputsMatchRootLock = builtins.all (name: let
    projectRootInputs = projectLock.nodes.root.inputs or {};
    projectInput = (projectLock.nodes or {}).${name} or {};
    rootInput = (lock.nodes or {}).${name} or {};
  in
    lib.hasInfix "${name}:" devenvYamlText
    && (projectRootInputs.${name} or null) == name
    && (projectInput.locked.rev or null) == (rootInput.locked.rev or null)
    && (rootInput.locked.rev or null) != null)
  machineBuildInputs;
  devenvSourceText = devenvText + devenvYamlText;
  pinnedDevenv = inputs.devenv.packages.${pkgs.stdenv.hostPlatform.system}.devenv;
  devenvOverlay = import ../overlays/default.nix {inherit inputs;};
  overlayDevenv = isDarwin: system: previousDevenv:
    (devenvOverlay {
      stdenv.hostPlatform = {inherit isDarwin system;};
    } {devenv = previousDevenv;}).devenv;
  darwinDevenv = overlayDevenv true "aarch64-darwin" "nixpkgs-darwin-devenv";
  linuxDevenv = overlayDevenv false pkgs.stdenv.hostPlatform.system "nixpkgs-linux-devenv";
  foundationPackages = import ../modules/roles/foundation-packages.nix {inherit pkgs;};
  manifestPath = ../secretspec.toml;
  manifestExists = builtins.pathExists manifestPath;
  manifestText =
    if manifestExists
    then builtins.readFile manifestPath
    else "";
  manifest =
    if manifestExists
    then builtins.fromTOML manifestText
    else {};
  profiles = manifest.profiles or {};
  providers = manifest.providers or {};
  lockPath = ../flake.lock;
  lockExists = builtins.pathExists lockPath;
  lock =
    if lockExists
    then builtins.fromJSON (builtins.readFile lockPath)
    else {};
  devenvLockPath = ../devenv.lock;
  devenvLockExists = builtins.pathExists devenvLockPath;
  projectLock =
    if devenvLockExists
    then builtins.fromJSON (builtins.readFile devenvLockPath)
    else {};
  rootDevenvNode = lock.nodes.devenv or {};
  devenvRootInputs = projectLock.nodes.root.inputs or {};
  devenvInputNixpkgs = (projectLock.nodes or {}).${devenvRootInputs.nixpkgs or "nixpkgs"} or {};
  rootNixpkgsInput = (lock.nodes.root.inputs or {}).nixpkgs or "nixpkgs";
  rootNixpkgs = (lock.nodes or {}).${rootNixpkgsInput} or {};
  rootNixpkgsRevision = rootNixpkgs.locked.rev or "";
  devenvNixpkgsMatchesRoot =
    lockExists
    && devenvLockExists
    && lib.toLower (devenvInputNixpkgs.locked.owner or "") == lib.toLower (rootNixpkgs.locked.owner or "")
    && (devenvInputNixpkgs.locked.repo or null) == (rootNixpkgs.locked.repo or null)
    && (devenvInputNixpkgs.locked.rev or null) == (rootNixpkgs.locked.rev or null)
    && (devenvInputNixpkgs.original.owner or null) == "NixOS"
    && (devenvInputNixpkgs.original.repo or null) == "nixpkgs"
    && lib.hasInfix "url: github:NixOS/nixpkgs/${rootNixpkgsRevision}" devenvYamlText;
  profileRoutesTo = profileName: expectedVault: let
    profile = profiles.${profileName} or {};
    providerNames = (profile.defaults or {}).providers or [];
    routeUris = map (providerName: providers.${providerName} or null) providerNames;
  in
    routeUris == ["onepassword://${expectedVault}"];
  providersAreUriOnly =
    builtins.all
    (uri: builtins.isString uri && builtins.match "onepassword://[A-Za-z0-9_-]+" uri != null)
    (builtins.attrValues providers);
  profilesDeclareExpectedFields = builtins.all (name: let
    profile = profiles.${name};
    expected =
      if name == "Homelab"
      then ["OPNIX_SERVICE_ACCOUNT_TOKEN" "TAILSCALE_OAUTH_CLIENT_ID" "TAILSCALE_OAUTH_CLIENT_SECRET" "defaults"]
      else if name == "MegamanX"
      then ["MEGAMANX_SUDO_PASSWORD" "defaults"]
      else ["defaults"];
  in
    builtins.attrNames profile == expected)
  (builtins.attrNames profiles);
  homelabOpnixToken = (profiles.Homelab or {}).OPNIX_SERVICE_ACCOUNT_TOKEN or {};
  homelabOpnixTokenIsReferenceOnly =
    (homelabOpnixToken.ref or {})
    == {
      item = "1Password Service Account - Opnix";
      field = "credential";
    }
    && (homelabOpnixToken.providers or []) == ["homelab"]
    && (homelabOpnixToken ? description)
    && !(homelabOpnixToken ? value);
  megamanxSudoPassword = (profiles.MegamanX or {}).MEGAMANX_SUDO_PASSWORD or {};
  megamanxSudoPasswordIsReferenceOnly =
    (megamanxSudoPassword.ref or {})
    == {
      item = "MegamanX Sudo Password";
      field = "password";
    }
    && (megamanxSudoPassword.providers or []) == ["megamanx"]
    && (megamanxSudoPassword ? description)
    && !(megamanxSudoPassword ? value);
  profilesHaveNoResolvedValuesOrCredentials =
    builtins.all
    (profile: let
      defaults = profile.defaults or {};
    in
      builtins.attrNames defaults
      == ["inherit" "providers"]
      && defaults."inherit" == false
      && builtins.isList defaults.providers
      && builtins.all builtins.isString defaults.providers)
    (builtins.attrValues profiles);
  roleUsesSelectedDevenv =
    builtins.any
    (package: package.drvPath == pkgs.devenv.drvPath)
    foundationPackages.common;
  outputSelectsPinnedDevenvOnAllPlatforms =
    lib.hasInfix "devenv = pkgs.devenv;" outputsText
    && !(lib.hasInfix "if isDarwin then pkgs.devenv" outputsText);
  devenvDoesNotLoadSecretsGlobally =
    lib.hasInfix "secretspec:\n  enable: false" devenvYamlText
    && !(lib.hasInfix "SECRETSPEC_" devenvSourceText)
    && !(lib.hasInfix "OP_SERVICE_ACCOUNT_TOKEN" devenvSourceText);

  assertResult = name: condition:
    if condition
    then ''echo "  ${name}: OK"''
    else ''echo "  FAIL: ${name}"; exit 1'';
in {
  machinesSecretProfiles = pkgs.runCommand "machines-secret-profiles" {} ''
    echo "=== Testing Machines foundation pin and SecretSpec profiles ==="
    ${assertResult "root flake pins devenv to stable v2.4.0" (lib.hasInfix ''devenv.url = "github:cachix/devenv/v2.4.0";'' flakeText)}
    ${assertResult "flake lock records the v2.4.0 ref" (lockExists && (rootDevenvNode.original.ref or null) == "v2.4.0")}
    ${assertResult "Devenv project nixpkgs owner, repository, and revision match the root flake lock" devenvNixpkgsMatchesRoot}
    ${assertResult "pinned devenv is selected on every supported platform" outputSelectsPinnedDevenvOnAllPlatforms}
    ${assertResult "Darwin overlay keeps the nixpkgs devenv package" (darwinDevenv == "nixpkgs-darwin-devenv")}
    ${assertResult "Linux overlay selects the pinned devenv package" (linuxDevenv.drvPath == pinnedDevenv.drvPath)}
    ${assertResult "foundation role consumes the selected devenv package" roleUsesSelectedDevenv}
    ${assertResult "Machines projection receives the NixOS facter input with nixpkgs following devenv nixpkgs" machinesProjectionReceivesFacterInput}
    ${assertResult "Devenv locks all inputs needed by the shared Machines package overlay" machineBuildInputsMatchRootLock}
    ${assertResult "SecretSpec has a Homelab 1Password profile route" (manifestExists && profileRoutesTo "Homelab" "Homelab")}
    ${assertResult "SecretSpec omits the unused Personal profile" (manifestExists && !(profiles ? Personal))}
    ${assertResult "SecretSpec keeps the MegamanX sudo profile routed to Private" (manifestExists && profileRoutesTo "MegamanX" "Private")}
    ${assertResult "MegamanX sudo password is referenced from Private without embedding a value" megamanxSudoPasswordIsReferenceOnly}
    ${assertResult "SecretSpec providers contain only 1Password vault URIs" (manifestExists && providersAreUriOnly)}
    ${assertResult "SecretSpec profiles declare the expected Homelab and MegamanX fields" (manifestExists && profilesDeclareExpectedFields && profilesHaveNoResolvedValuesOrCredentials)}
    ${assertResult "Homelab opnix service-account token is a reference-only field" homelabOpnixTokenIsReferenceOnly}
    ${assertResult "devenv explicitly keeps global SecretSpec loading disabled" devenvDoesNotLoadSecretsGlobally}
    touch $out
  '';
}
