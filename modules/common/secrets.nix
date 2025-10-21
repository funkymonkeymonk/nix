{ config, lib, ... }:

let
  cfg = config.myConfig.secrets;

  # Try to load secrets from various sources
  secretsFile = ../secrets.nix;
  secretsFromFile = if builtins.pathExists secretsFile
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
    apiKeys = {
      openai = null;
      anthropic = null;
      huggingface = null;
    };
    databases = {};
    cloud = {
      aws = {
        accessKeyId = null;
        secretAccessKey = null;
        region = "us-east-1";
      };
      digitalocean = {
        token = null;
      };
    };
    personal = {
      homeAddress = null;
      phoneNumbers = {
        primary = null;
        work = null;
      };
      birthday = null;
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

    apiKeys = {
      openai = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.apiKeys.openai;
        readOnly = true;
        description = "OpenAI API key";
      };
      anthropic = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = secrets.apiKeys.anthropic;
        readOnly = true;
        description = "Anthropic API key";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Set up environment variables for API keys
    environment.sessionVariables = lib.mkMerge [
      (lib.mkIf (cfg.apiKeys.openai != null) {
        OPENAI_API_KEY = cfg.apiKeys.openai;
      })
      (lib.mkIf (cfg.apiKeys.anthropic != null) {
        ANTHROPIC_API_KEY = cfg.apiKeys.anthropic;
      })
    ];
  };
}