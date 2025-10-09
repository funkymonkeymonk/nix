{
  description = "Will Weaver system setup flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core.url = "github:homebrew/homebrew-core";
    homebrew-core.flake = false;
    homebrew-cask.url = "github:homebrew/homebrew-cask";
    homebrew-cask.flake = false;

    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    mac-app-util,
    ...
  }: let
    configuration = {pkgs, ...}: {
      nix.enable = false;
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      system.defaults = {
        NSGlobalDomain.AppleInterfaceStyle = "Dark";
        dock = {
          autohide = true;
        };
      };

      nixpkgs.config.allowUnfree = true;
      # Access unstable pkgs with pkgs.unstable
      nixpkgs.overlays = [
        (final: _prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) system config;
          };
        })
      ];

      environment.systemPackages = with pkgs; [
        # _1password-gui
        _1password-cli
        vim
        emacs
        google-chrome
        trippy
        logseq
        ripgrep
        fd
        coreutils
        clang
        git
        slack
        gh
        devenv
        direnv
        home-manager
        colima
        go-task
        the-unarchiver
        hidden-bar
        glow
        rclone
        zinit
        bat
        jq
        tree
        watchman
        jnv
        goose-cli
        zinit
        antigen
        alacritty-theme
        #atuin - check this out later
        claude-code
        k3d
        kubectl
        kubernetes-helm
        k9s
      ];
    };
  in {
    darwinConfigurations."Will-Stride-MBP" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        ./homebrew.nix
        ./aerospace.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.primaryUser = "willweaver";
        }
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.willweaver = import ./home.nix;
          users.users.willweaver.home = "/Users/willweaver/";
        }
      ];
    };

    darwinConfigurations."MegamanX" = nix-darwin.lib.darwinSystem {
      modules = [
        mac-app-util.darwinModules.default
        configuration
        ./homebrew.nix
        ./aerospace.nix
        {
	  nixpkgs.hostPlatform = "aarch64-darwin";
	  system.primaryUser = "monkey";
        }
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.monkey = import ./home.nix;
          users.users.monkey.home = "/Users/monkey/";
        }
        {
          homebrew.casks = [
            "autodesk-fusion"
            "deezer"
            "discord"
            "ha-menu"
            "xtool-studio"
            "orcaslicer"
            "openscad"
            "ollama-app"
            "block-goose"
            "obs"
            "pocket-casts"
            "steam"
            "sensei"
          ];
        }
      ];
    };
  };
}
