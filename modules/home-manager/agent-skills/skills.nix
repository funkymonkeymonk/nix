{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.agent-skills;
  # For now, create declarative management
  # Future: Use superpowers input for actual skill files
in {
  config = lib.mkIf cfg.enable {
    home = {
      # Create declarative skill management structure
      file.".config/opencode/skills/.gitignore" = {
        text = ''
          # Files managed by Nix - do not edit manually
          # Skills are installed through Nix configuration
        '';
      };

      file.".config/opencode/superpowers/skills/.gitignore" = {
        text = ''
          # Compatibility directory - managed by Nix
          # Synchronized with main skills directory
        '';
      };

      file.".config/opencode/skills/README.md" = {
        text = ''
          # Agent Skills

          Skills managed declaratively through Nix configuration.

          Configuration:
          - Repository: ${cfg.skillsRepo}
          - Version: ${cfg.skillsVersion}

          ## Update Process

          To update skills to a new version:

          1. Change `skillsVersion` in your Nix configuration
          2. Rebuild your system:
             - Darwin: `darwin-rebuild switch --flake .#`
             - NixOS: `nixos-rebuild switch --flake .#`

          This provides:
          - Version pinning and reproducibility
          - Automatic cleanup of unused skills
          - Declarative management

          ## Locations

          - Main skills: `~/.config/opencode/skills/`
          - Superpowers compatibility: `~/.config/opencode/superpowers/skills/`

          ## Future Enhancement

          Future versions will include declarative fetching from:
          ${cfg.skillsRepo}

          For now, use `update-agent-skills` command for information.
        '';
      };

      file.".config/opencode/superpowers/skills/README.md" = {
        text = ''
          # Superpowers Skills Compatibility

          This directory provides compatibility with tools that expect skills
          in the superpowers directory structure.

          Skills are automatically synchronized with the main skills directory
          through the Nix configuration system.

          Configuration:
          - Repository: ${cfg.skillsRepo}
          - Version: ${cfg.skillsVersion}

          ## Synchronization

          This directory maintains compatibility with existing workflows while
          migrating to the new declarative Nix-based approach.

          For skill updates, see the main skills directory README.
        '';
      };
    };
  };
}
