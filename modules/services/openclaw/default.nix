# OpenClaw service modules
# Imports shared configuration and hardening overlays
{...}: {
  imports = [
    ./shared.nix
    ./hardening.nix
    ./legacy.nix # Legacy npm-based module (deprecated, for backward compatibility)
  ];
}
