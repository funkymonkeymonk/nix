# OpenClaw service modules
# Imports shared configuration and hardening overlays.
#
# Note: the real OpenClaw gateway service comes from the upstream
# nix-openclaw flake input (inputs.nix-openclaw.nixosModules.openclaw-gateway
# / homeManagerModules.openclaw), wired directly in flake.nix. This directory
# only provides the myConfig.openclaw.* shared-config and hardening overlay
# options — it does not define a service itself.
{...}: {
  imports = [
    ./shared.nix
    ./hardening.nix
  ];
}
