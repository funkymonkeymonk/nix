{
  pkgs,
  inputs,
  ...
}: let
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  manifest = builtins.fromTOML (builtins.readFile ../secretspec.toml);
  homelabBootstrapSecret = manifest.profiles.Homelab.OPNIX_SERVICE_ACCOUNT_TOKEN or null;
  tailscaleOAuthClientId = manifest.profiles.Homelab.TAILSCALE_OAUTH_CLIENT_ID or null;
  tailscaleOAuthClientSecret = manifest.profiles.Homelab.TAILSCALE_OAUTH_CLIENT_SECRET or null;
  drlightTailscaleOverrides = catalog.drlight.overrides.tailscale or {};
  pinnedDevenv = inputs.devenv.packages.${pkgs.stdenv.hostPlatform.system}.devenv;
  homelabMachines = [
    "zero"
    "drlight"
    "type-nas"
    "type-server"
    "type-server-arm"
  ];
  personalMachines = [
    "bootstrap"
    "type-desktop"
    "installer-iso"
    "wweaver"
    "darwin-server"
  ];
  profileChecks = assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Homelab") homelabMachines;
  assert builtins.all (name: (builtins.getAttr name catalog).secretProfile == "Personal") personalMachines;
  assert !(manifest.profiles ? Personal);
  assert catalog.MegamanX.secretProfile == "MegamanX";
  assert homelabBootstrapSecret != null;
  assert homelabBootstrapSecret.ref.item == "1Password Service Account - Opnix";
  assert homelabBootstrapSecret.ref.field == "credential";
  assert homelabBootstrapSecret.providers == ["homelab"];
  assert tailscaleOAuthClientId != null;
  assert tailscaleOAuthClientId.ref.item == "Tailscale Oauth";
  assert tailscaleOAuthClientId.ref.field == "Client ID";
  assert tailscaleOAuthClientId.providers == ["homelab"];
  assert tailscaleOAuthClientSecret != null;
  assert tailscaleOAuthClientSecret.ref.item == "Tailscale Oauth";
  assert tailscaleOAuthClientSecret.ref.field == "Client secret";
  assert tailscaleOAuthClientSecret.providers == ["homelab"];
  assert drlightTailscaleOverrides.authKeyMode == "devenv-oauth";
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
