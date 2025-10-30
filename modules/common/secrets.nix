{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.secrets;

  # Try to load secrets from various sources
  secretsFile = ../secrets.nix;
  secretsFromFile =
    if builtins.pathExists secretsFile
    then import secretsFile
    else {};

  # Default empty secrets structure
  defaultSecrets = {
    git = {
      userName = null;
      userEmail = null;
      githubToken = null;
    };
    ssh = {
      privateKey = null;
      publicKey = null;
    };
  };

  # Merge defaults with loaded secrets
  secrets = lib.recursiveUpdate defaultSecrets secretsFromFile;
in {
  options.myConfig.secrets = {
    # Allow overriding secrets file path
    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to secrets file";
    };

    # Expose secrets as read-only options
    git = {
      userName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.git.userName;
        readOnly = true;
        description = "Git user name";
      };
      userEmail = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.git.userEmail;
        readOnly = true;
        description = "Git user email";
      };
      githubToken = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.git.githubToken;
        readOnly = true;
        description = "GitHub personal access token";
      };
    };

    ssh = {
      privateKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.ssh.privateKey;
        readOnly = true;
        description = "SSH private key";
      };
      publicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.ssh.publicKey;
        readOnly = true;
        description = "SSH public key";
      };
    };
  };
}
