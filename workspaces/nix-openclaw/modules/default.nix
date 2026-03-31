# Top-level module entry point
# Import this from any host configuration to get all common modules + roles.
# Platform-specific modules (os/darwin.nix, os/nixos.nix, services) are still
# imported separately by each host since they depend on the platform.
{
  imports = [
    # Core and common
    ./common/core.nix
    ./common/options.nix
    ./common/users.nix
    ./common/shell.nix
    ./common/onepassword.nix
    ./common/cachix.nix

    # Home-manager shared settings
    ./home-manager

    # Role modules (each gated by myConfig.roles.<name>.enable)
    ./roles
  ];
}
