{
  description = "Will Weaver system setup flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

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
      system.configurationRevision = self.rev or self.dirtyRev or null;
      system.stateVersion = "25.05";

      nixpkgs.config.allowUnfree = true;

      # Access unstable pkgs with pkgs.unstable
      nixpkgs.overlays = [
        (final: _prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) system config;
          };
        })
      ];
<<<<<<< HEAD

      environment.systemPackages = with pkgs; [
        vim
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
        unstable.fzf
      ];

      programs._1password = {
        enable = true;
        package = pkgs.unstable._1password-cli;
      };

      programs._1password-gui = {
        enable = true;
        package = pkgs.unstable._1password-gui;
      };
=======
>>>>>>> 34a9bce (Nixos (#3))
    };
  in {
    darwinConfigurations."Will-Stride-MBP" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        ./minimal.nix
        ./darwin.nix
        ./homebrew.nix
        ./emacs.nix
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
        ./minimal.nix
        ./darwin.nix
        ./homebrew.nix
        ./emacs.nix
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

    nixosConfigurations."drlight" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos.nix
        ./hardware-configuration.nix
        {
          users.users.monkey = {
            isNormalUser = true;
            description = "monkey";
            extraGroups = ["networkmanager" "wheel"];
          };
        }
        {
          networking.hostName = "drlight"; # Define your hostname.
          # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
          networking.networkmanager.enable = true;
          time.timeZone = "America/New_York";

          services.openssh.enable = true;
        }
        {
          nixpkgs.hostPlatform = "x86_64-linux";
        }
        configuration
        ./minimal.nix
        ./1password.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.monkey = import ./linux-home.nix;
        }
      ];
    };
  };
}
