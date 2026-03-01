{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.openclaw-host;
in {
  options.myConfig.openclaw-host = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenClaw host configuration";
    };

    documents = mkOption {
      type = types.path;
      default = ./documents;
      description = "Path to OpenClaw documents directory";
    };

    configPath = mkOption {
      type = types.str;
      default = "";
      description = "Path to OpenClaw config file";
    };
  };

  config = mkIf cfg.enable {
    programs.openclaw = {
      inherit (cfg) documents;

      instances.default = {
        enable = true;
        configPath = mkIf (cfg.configPath != "") cfg.configPath;
        config = {
          plugins = {
            allow = ["matrix"];
          };
          gateway = {
            mode = "local";
          };
        };
      };
    };

    # Activation script for matrix plugin
    home.activation.installMatrixPlugin = lib.hm.dag.entryAfter ["installPackages"] ''
      cd ~/.openclaw/extensions/matrix
      if [ -f package.json ]; then
        PATH="$HOME/.nix-profile/bin:$PATH" npm install --ignore-scripts 2>/dev/null || true
        PATH="$HOME/.nix-profile/bin:$PATH" node node_modules/@matrix-org/matrix-sdk-crypto-nodejs/download-lib.js 2>/dev/null || true
      fi
    '';
  };
}
