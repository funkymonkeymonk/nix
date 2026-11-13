{
  pkgs,
  inputs,
  ...
}: let
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  manifest = builtins.fromTOML (builtins.readFile ../secretspec.toml);
  opnixBootstrapSecret = manifest.profiles.Opnix.OPNIX_SERVICE_ACCOUNT_TOKEN or null;
  tailscaleOAuthClientId = manifest.profiles.Opnix.TAILSCALE_OAUTH_CLIENT_ID or null;
  tailscaleOAuthClientSecret = manifest.profiles.Opnix.TAILSCALE_OAUTH_CLIENT_SECRET or null;
  drlightTailscaleOverrides = catalog.drlight.overrides.tailscale or {};
  pinnedDevenv = inputs.devenv.packages.${pkgs.stdenv.hostPlatform.system}.devenv;
  opnixMachines = [
    "zero"
    "drlight"
    "type-nas"
    "type-server"
    "type-server-arm"
    "Lydia"
  ];
  personalMachines = [
    "bootstrap"
    "type-desktop"
    "installer-iso"
    "wweaver"
  ];
  profileChecks = assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Opnix") opnixMachines;
  assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Personal") personalMachines;
  assert !(manifest.profiles ? Personal);
  assert !(manifest.profiles ? Homelab);
  assert catalog.wweaver.secretProfile == "Personal";
  assert !(manifest.profiles ? Employee);
  assert manifest.providers.opnix == "onepassword://Opnix";
  assert manifest.providers.employee == "onepassword://Employee";
  assert manifest.providers."service-accounts" == "onepassword://vio73ncjh7hofsrzj7ogf473w4";
  assert catalog.MegamanX.secretProfile == "MegamanX";
  assert opnixBootstrapSecret != null;
  assert opnixBootstrapSecret.ref.item == "opcec4mg3aykq2qkbnhri2vtn4";
  assert opnixBootstrapSecret.ref.field == "credential";
  assert opnixBootstrapSecret.providers == ["service-accounts"];
  assert tailscaleOAuthClientId != null;
  assert tailscaleOAuthClientId.ref.item == "Tailscale Oauth";
  assert tailscaleOAuthClientId.ref.field == "Client ID";
  assert tailscaleOAuthClientId.providers == ["opnix"];
  assert tailscaleOAuthClientSecret != null;
  assert tailscaleOAuthClientSecret.ref.item == "Tailscale Oauth";
  assert tailscaleOAuthClientSecret.ref.field == "Client secret";
  assert tailscaleOAuthClientSecret.providers == ["opnix"];
  assert drlightTailscaleOverrides.enable == true;
  assert drlightTailscaleOverrides.authKeyTags == ["tag:home-lab" "tag:media-center"]; true;
in {
  machineOps = assert profileChecks;
    pkgs.runCommand "machine-ops-safety-tests" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq];
    } ''
      MACHINE_OPS_SCRIPT=${../scripts/machine-ops.sh} bash ${./test-machine-ops.sh}
      touch $out
    '';

  secretspecEmptyProfiles =
    pkgs.runCommand "secretspec-empty-profile-safety-tests" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils];
    } ''
      SECRETSPEC_BIN=${pinnedDevenv}/bin/secretspec \
      SECRETSPEC_MANIFEST=${../secretspec.toml} \
      COREUTILS_BIN=${pkgs.coreutils}/bin \
        ${pkgs.bash}/bin/bash ${./test-secretspec-empty-profiles.sh}
      touch $out
    '';
}
