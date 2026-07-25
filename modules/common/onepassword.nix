{
  config,
  options,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
  inherit (config.myConfig) isDarwin;
  # Check if the opnix module is available (onepassword-secrets option exists)
  hasOpnix = builtins.hasAttr "onepassword-secrets" (options.services or {});
in {
  options.myConfig.onepassword = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable 1Password integration";
    };

    enableGUI = mkOption {
      type = types.bool;
      default = true;
      description = "Enable 1Password GUI application";
    };

    enableSSHAgent = mkOption {
      type = types.bool;
      default = true;
      description = "Enable 1Password SSH agent";
    };

    enableGitSigning = mkOption {
      type = types.bool;
      default = true;
      description = "Enable git commit signing with 1Password";
    };

    signingKey = mkOption {
      type = types.str;
      default = "";
      description = "SSH key name for git signing in 1Password";
    };

    sudoPasswordRef = mkOption {
      type = types.str;
      default = "";
      description = ''
        1Password reference for the sudo password used by the system:switch task.
        If empty (default), falls back to op://Private/<hostname> Sudo Password/password.
        Override this for machines with different vault or item names,
        e.g. "op://Employee/wweaver Sudo Password/password".
      '';
    };

    defaultVault = mkOption {
      type = types.str;
      default = "Personal";
      description = "Default 1Password vault for all secrets. Prepended to any opnix secret reference that does not start with 'op://'. Set per-machine to change the vault for all unqualified references.";
    };

    tokenFile = mkOption {
      type = types.path;
      default = "/etc/opnix-token";
      description = ''
        Path to the 1Password service account token file.
        This file should contain a 1Password service account token and have restricted permissions (0600).
        The token is used by opnix to fetch secrets at runtime.

        To create a service account token:
        1. Go to https://my.1password.com/developer-tools/service-accounts
        2. Create a service account with access to the vaults containing your secrets
        3. Copy the token and save it to this file

        The service will fail gracefully if the token file doesn't exist or is invalid.
      '';
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          reference = mkOption {
            type = types.str;
            description = "1Password reference (e.g., 'op://vault/item/field')";
          };
          path = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Path where the secret should be written.
              If null, opnix uses its outputDir (default: /var/lib/opnix/secrets) plus the secret name.
            '';
          };
          mode = mkOption {
            type = types.str;
            default = "0600";
            description = "File permissions for the secret";
          };
          owner = mkOption {
            type = types.str;
            default = "root";
            description = "Owner of the secret file";
          };
          group = mkOption {
            type = types.str;
            default = "root";
            description = "Group of the secret file";
          };
          services = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Services that depend on this secret (will be restarted when secret changes)";
          };
        };
      });
      default = {};
      description = ''
        Secrets to fetch from 1Password using opnix.
        Secrets are fetched at boot time and written to the specified paths.
        The 1Password service account must have access to the referenced vaults.

        Example:
        {
          myApiKey = {
            reference = "op://Private/MyAPI/credential";
            path = "/run/secrets/my-api-key";
            mode = "0600";
            owner = "myuser";
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # On NixOS, use programs._1password which sets up PAM integration and the CLI.
    # On Darwin, the CLI is provided via environment.systemPackages since
    # programs._1password is a NixOS-only option.
    # Use mkIf (not optionalAttrs) so isDarwin is evaluated lazily, avoiding
    # infinite recursion during module argument binding.
    (mkIf (!isDarwin) {
      programs._1password = {
        enable = true;
        package = pkgs._1password-cli;
      };
    })
    (mkIf isDarwin {
      environment.systemPackages = [pkgs._1password-cli];
    })
    (optionalAttrs hasOpnix {
      # Enable opnix secrets service when the module is available (NixOS only).
      # Defaults to disabled — roles that need 1Password secrets (e.g. tailscale)
      # must explicitly enable this by setting services.onepassword-secrets.enable = true.
      # To get a token: https://developer.1password.com/docs/service-accounts/get-started/
      services.onepassword-secrets = {
        enable = mkDefault false;
        inherit (cfg) tokenFile;
        secrets =
          lib.mapAttrs (
            _name: secret:
              secret
              // {
                reference =
                  if lib.hasPrefix "op://" secret.reference
                  then secret.reference
                  else "op://${cfg.defaultVault}/${secret.reference}";
              }
          )
          cfg.secrets;
      };
    })
  ]);
}
