{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.approval-system;

  # Scripts
  approve-request = pkgs.writeScriptBin "approve-request" (builtins.readFile ./bin/approve-request);
  approvald = pkgs.writeScriptBin "approvald" (builtins.readFile ./bin/approvald);

  # Config file content
  configToml = let
    ntfyConfig = optionalString (cfg.notification.type == "ntfy") ''

      [notification.ntfy]
      server = "${cfg.notification.ntfy.server}"
      topic = "${cfg.notification.ntfy.topic}"
    '';
    pushoverConfig = optionalString (cfg.notification.type == "pushover") "
\n[notification.pushover]\n# Keys loaded from files for security\n";
    accountLine = optionalString (cfg.onepassword.account != null) ''account = "${cfg.onepassword.account}"'';
  in ''
    # Approval System Configuration

    [notification]
    type = "${cfg.notification.type}"
    ${ntfyConfig}${pushoverConfig}

    [onepassword]
    enabled = ${boolToString cfg.onepassword.enable}
    ${accountLine}

    [policy]
    auto_approve = [ ${concatStringsSep ", " (map (x: ''"${x}"'') cfg.policy.autoApprove)} ]
    require_justification = ${boolToString cfg.policy.requireJustification}
    timeout = ${toString cfg.policy.timeout}
  '';

  # Credentials file content
  credentialsEnv =
    optionalString (cfg.notification.type == "ntfy" && cfg.notification.ntfy.tokenFile != null)
    "NTFY_TOKEN=$(cat ${toString cfg.notification.ntfy.tokenFile})\n"
    + optionalString (cfg.notification.type == "pushover" && cfg.notification.pushover.userKeyFile != null)
    "PUSHOVER_USER_KEY=$(cat ${toString cfg.notification.pushover.userKeyFile})\n"
    + optionalString (cfg.notification.type == "pushover" && cfg.notification.pushover.appTokenFile != null)
    "PUSHOVER_APP_TOKEN=$(cat ${toString cfg.notification.pushover.appTokenFile})\n";
in {
  options.services.approval-system = {
    enable = mkEnableOption "phone-based approval system for sudo and secrets";

    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run the approval daemon as";
    };

    notification = {
      type = mkOption {
        type = types.enum ["ntfy" "pushover" "matrix" "discord"];
        default = "ntfy";
        description = "Notification service to use for approval requests";
      };

      ntfy = {
        server = mkOption {
          type = types.str;
          default = "https://ntfy.sh";
          description = "ntfy server URL (self-hosted or public)";
        };

        topic = mkOption {
          type = types.str;
          default = "approval-requests";
          description = "ntfy topic for approval notifications";
        };

        tokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to file containing ntfy access token";
        };
      };

      pushover = {
        userKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to file containing Pushover user key";
        };

        appTokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to file containing Pushover app token";
        };
      };
    };

    onepassword = {
      enable = mkEnableOption "1Password integration for secret retrieval";
      account = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "1Password account identifier";
      };
    };

    policy = {
      autoApprove = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["uptime" "whoami" "ls"];
        description = "Commands that are auto-approved without phone notification";
      };

      requireJustification = mkOption {
        type = types.bool;
        default = true;
        description = "Require justification for approval requests";
      };

      timeout = mkOption {
        type = types.int;
        default = 300;
        description = "Approval timeout in seconds (default: 5 minutes)";
      };
    };

    sudoIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable sudo integration (wraps sudo command)";
    };
  };

  config = mkIf cfg.enable (let inherit (config) environment; in {
    # Install dependencies
    environment = {
      systemPackages = with pkgs; [
        _1password-cli
        jq
        socat
        openssl
        curl
        approve-request
        approvald
      ];

      etc = {
        "approval/config.toml" = {
          text = configToml;
          mode = "0600";
          user = cfg.user;
        };

        "approval/credentials.env" = {
          text = credentialsEnv;
          mode = "0400";
          user = cfg.user;
        };
      };

      shellInit = ''
        # Approval system functions
        approve-sudo() {
          local cmd="$*"
          if [[ -S "''${APPROVAL_SOCKET:-/run/user/$(id - u)/approvald/request.sock}" ]]; then
            approve-request sudo --command "$cmd"
          else
            echo "Approval daemon not running, using regular sudo"
            sudo "$@"
          fi
        }

        get-secret() {
          local vault="$1"
          local item="$2"
          local field="$3"
          approve-request secret --vault "$vault" --item "$item" --field "$field"
        }

        alias as='approve-sudo'
        alias gs='get-secret'
      '';
    };

    # Create directories
    systemd.tmpfiles.rules = [
      "d /run/approvald 0750 ${cfg.user} ${cfg.user} -"
      "d /var/lib/approvald 0750 ${cfg.user} ${cfg.user} -"
      "d /home/${cfg.user}/.config/approval 0750 ${cfg.user} ${cfg.user} -"
    ];

    # User service for approval daemon
    systemd.user.services.approvald = {
      description = "Approval daemon for phone-based authorization";

      serviceConfig = {
        Type = "simple";
        ExecStart = "${approvald}/bin/approvald start";
        ExecStop = "${approvald}/bin/approvald stop";
        Restart = "always";
        RestartSec = 5;

        Environment = [
          "APPROVAL_CONFIG=/etc/approval/config.toml"
          "APPROVAL_SOCKET=/run/user/%U/approvald/request.sock"
          "APPROVAL_LOG=/home/${cfg.user}/.local/log/approvald.log"
          "PATH=${makeBinPath (with pkgs; [_1password-cli jq socat openssl curl])}"
        ];

        EnvironmentFile = "-/etc/approval/credentials.env";
      };

      wantedBy = ["default.target"];
    };
  };
}
