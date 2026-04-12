{
  description = "OpenClaw local";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    opnix.url = "github:brizzbuzz/opnix";
    opnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-openclaw,
      opnix,
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-openclaw.overlays.default ];
      };
    in
    {
      homeConfigurations."monkey" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          nix-openclaw.homeManagerModules.openclaw
          opnix.homeManagerModules.default
          {
            home.username = "monkey";
            home.homeDirectory = "/Users/monkey";
            home.stateVersion = "24.11";
            programs.home-manager.enable = true;

            programs.openclaw = {
              documents = ./documents;

              config = {
                gateway = {
                  mode = "local";
                  auth = {
                    token = "945308a1b9a7a21fae9bac633991698f06b3b37ab5b3c8d82aa423d5f01e7a17";
                  };
                };

                # Discord channel configuration
                channels.discord = {
                  tokenFile = "/Users/monkey/.config/openclaw/secrets/discord-bot-token";
                  # Allow DMs from specific users (your Discord user ID)
                  # Get your ID: https://support.discord.com/hc/en-us/articles/206346498-Where-can-I-find-my-User-Server-Message-ID
                  allowFrom = [ ];
                  # DM pairing for security
                  dmPolicy = "pairing";
                };

                # Inception provider configuration
                agent = {
                  model = "inception/default";
                };

                provider = {
                  inception = {
                    name = "inception";
                    baseURL = "https://api.inceptionlabs.ai/v1";
                    apiKeyFile = "/Users/monkey/.config/openclaw/secrets/inception-api-key";
                  };
                };
              };

              instances.default = {
                enable = true;
                plugins = [
                  # Example plugins - enable as needed
                  # { source = "github:openclaw/nix-steipete-tools?dir=tools/peekaboo"; }
                  # { source = "github:openclaw/nix-steipete-tools?dir=tools/summarize"; }
                ];
              };
            };

            # Opnix secrets configuration
            programs.onepassword-secrets = {
              enable = true;
              # Token stored in restricted location (not ~/.config/)
              tokenFile = "/Users/monkey/.local/share/opnix/token";
              secrets = {
                # Discord bot token from 1Password
                openclawDiscordToken = {
                  reference = "op://openclaw/OpenClaw/discord-bot-token";
                  path = ".config/openclaw/secrets/discord-bot-token";
                  mode = "0600";
                };
                # Inception API key from 1Password
                openclawInceptionKey = {
                  reference = "op://openclaw/OpenClaw/inception-api-key";
                  path = ".config/openclaw/secrets/inception-api-key";
                  mode = "0600";
                };
              };
            };
          }
        ];
      };
    };
}
