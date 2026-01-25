{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.agent-skills;

  # Create update script with proper Nix configuration management
  updateScript = pkgs.writeShellScriptBin "update-agent-skills" ''
    set -euo pipefail

    echo "=== Agent Skills Update ==="
    echo ""
    echo "Agent skills are now managed declaratively through Nix!"
    echo ""
    echo "Current configuration:"
    echo "  Repository: ${cfg.skillsRepo}"
    echo "  Version: ${cfg.skillsVersion}"
    echo ""
    echo "To update skills:"
    echo "1. Change skillsVersion in your Nix configuration"
    echo "2. For latest commit from main branch:"
    echo "   LATEST=$(git ls-remote ${cfg.skillsRepo} refs/heads/main | cut -f1 | cut -d' ' -f1)"
    echo "3. Rebuild with your platform's command:"
    echo "   - Darwin: darwin-rebuild switch --flake .#"
    echo "   - NixOS: nixos-rebuild switch --flake .#"
    echo ""
    echo "This declarative approach ensures:"
    echo "  - Reproducible deployments"
    echo "  - Automatic cleanup of unused skills"
    echo "  - Version pinning per configuration"
    echo ""
    echo "Note: Individual skills are installed through Nix home.file configuration"
    echo "      Check your Nix configuration for current skill locations"
  '';
in {
  config = lib.mkIf cfg.enable {
    # Add update script to home-manager context
    home.packages = [updateScript];
  };
}
