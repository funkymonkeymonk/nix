{
  description = "Will Weaver system setup flake";

  nixConfig = {
    extra-experimental-features = ["flakes" "nix-command"];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core.url = "github:homebrew/homebrew-core";
    homebrew-core.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-cask.flake = false;

    mac-app-util.url = "github:hraban/mac-app-util";

    superpowers.url = "github:obra/superpowers";
    superpowers.flake = false;

    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";

    devenv.url = "github:cachix/devenv";

    # NEW: Takeout container infrastructure for automated installs
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    zellij-pane-tracker.url = "github:funkymonkeymonk/zellij-pane-tracker";

    # External skill repositories (Option 2: Pure Nix approach)
    vercel-skills.url = "github:vercel-labs/skills";
    vercel-skills.flake = false;

    # Bifrost AI Gateway - high-performance LLM gateway
    bifrost.url = "github:maximhq/bifrost";

    # Pi plugins - extensions and skills for pi coding agent
    pi-plugins.url = "github:funkymonkeymonk/pi-plugins";
    inference-worker.url = "github:funkymonkeymonk/inference-worker";
    # Flake-parts (incremental migration — used for testing infrastructure first)
    flake-parts.url = "github:hercules-ci/flake-parts";

    # nix-unit: Eval-time unit testing framework
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.flake = false;

    # Himalaya TUI - terminal UI for email (companion to himalaya CLI)
    himalaya-tui.url = "github:pimalaya/himalaya-tui";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["aarch64-darwin" "x86_64-linux"];
      imports = [
        ./library/flake-module.nix
        ./library/outputs.nix
        ./library/machines/bootstrap.nix
        ./library/machines/cattle.nix
        ./library/machines/installer-iso.nix
        ./library/machines/zero.nix
        ./library/machines/darwin.nix
      ];
      flake = {};
    };
}
