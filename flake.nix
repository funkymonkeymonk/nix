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
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }:
  let
    configuration = { pkgs, ... }: {
      nix.enable = false;
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      nixpkgs.hostPlatform = "aarch64-darwin";
      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = with pkgs; [
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
        alacritty
        gh
        devenv
        direnv
        home-manager
        colima
        go-task
      ];

      # Homebrew configuration
      homebrew = {
        enable = true;
        onActivation.cleanup = "uninstall";

	    #caskArgs.no_quarantine = true;
        casks = [
	      "raycast"
          "1password"
          "1password-cli"
          "zed"
          "sigmaos"
          "orion"
        ];
      };
    # TODO generate ssh-key if it does not already exist
    # TODO register the ssh key in git locally
    # https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
    # https://discourse.nixos.org/t/how-to-set-up-a-system-wide-ssh-agent-that-would-work-on-all-terminals/14156/5
    };
  in
  {
    darwinConfigurations."Will-Stride-MBP" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        {
          system.primaryUser = "willweaver";
	    }
        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.willweaver = import ./home.nix;
          users.users.willweaver.home = "/Users/willweaver/";
        }
      ];
    };
  };
}
