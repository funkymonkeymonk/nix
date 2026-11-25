{
  config,
  lib,
  pkgs,
  ...
}: let
  jellyfinWebhookPlugin = pkgs.jellyfinWebhookPlugin;
  jellyfinPluginDirectory = "${config.services.jellyfin.dataDir}/plugins";
  jellyfinWebhookScripts = builtins.path {
    path = ./scripts;
    name = "media-app-reconciliation-scripts";
  };
  jellyfinWebhookConfig = pkgs.writeText "jellyfin-webhook-config.json" (builtins.toJSON {
    baseUrl = "http://127.0.0.1:8096";
    usernameFile = "/run/secrets/jellyfin-admin-username";
    passwordFile = "/run/secrets/jellyfin-admin-password";
    webhookUrlFile = "/run/secrets/jellyfin-discord-webhook";
    serverUrl = "https://${config.myConfig.caddy.apps.jellyfin.host}";
  });
in {
  config = lib.mkIf config.services.jellyfin.enable {
    systemd.tmpfiles.rules = [
      "d ${jellyfinPluginDirectory} 0755 jellyfin jellyfin - -"
    ];

    systemd.services.jellyfin = {
      preStart = lib.mkBefore ''
        ${pkgs.python3}/bin/python ${jellyfinWebhookScripts}/jellyfin_webhook_plugin_install.py \
          --source ${jellyfinWebhookPlugin} \
          --destination ${jellyfinPluginDirectory}/Webhook_${jellyfinWebhookPlugin.version}
      '';
      restartTriggers = [jellyfinWebhookPlugin];
    };

    systemd.services.jellyfin-discord-webhook-config-sync = {
      description = "Reconcile Jellyfin's ItemAdded Discord webhook";
      after = ["jellyfin.service" "opnix-secrets.service"];
      wants = ["jellyfin.service" "opnix-secrets.service"];
      requires = ["jellyfin.service" "opnix-secrets.service"];
      wantedBy = ["jellyfin.service"];
      restartTriggers = [jellyfinWebhookConfig jellyfinWebhookPlugin];
      serviceConfig = {
        Type = "oneshot";
        User = "jellyfin";
        Group = "jellyfin";
        SupplementaryGroups = ["media-auth-jellyfin"];
        UMask = "0077";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        ExecStart = "${pkgs.python3}/bin/python ${jellyfinWebhookScripts}/jellyfin_webhook_config.py --config ${jellyfinWebhookConfig}";
      };
    };

    myConfig.onepassword.secrets.jellyfinAdminUsername.services = lib.mkAfter ["jellyfin-discord-webhook-config-sync"];
    myConfig.onepassword.secrets.jellyfinAdminPassword.services = lib.mkAfter ["jellyfin-discord-webhook-config-sync"];
  };
}
