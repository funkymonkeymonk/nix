{
  description = "Will Weaver system setup flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

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

      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;

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
        karabiner-elements
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

      # Homebrew configuration
      homebrew = {
        enable = true;
        onActivation.cleanup = "uninstall";

        #caskArgs.no_quarantine = true;
        casks = [
          "1password"
          "raycast" # The version in nixpkgs is out of date
          "zed"
          "zen"
          "ollama-app"
        ];
      };

      #fonts.packages = with pkgs; [ nerd-fonts.droid-sans-mono ];

      # TODO generate ssh-key if it does not already exist
      # TODO register the ssh key in git locally
      # https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
      # https://discourse.nixos.org/t/how-to-set-up-a-system-wide-ssh-agent-that-would-work-on-all-terminals/14156/5
    };
  in {
    darwinConfigurations."Will-Stride-MBP" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        {
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
        {
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
