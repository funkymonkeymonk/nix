{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.myConfig.tubearchivist;
in {
  options.myConfig.tubearchivist.secrets = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "TubeArchivist username from 1Password";
    };

    password = lib.mkOption {
      type = lib.types.str;
      description = "TubeArchivist password from 1Password";
    };
  };

  config = lib.mkIf (cfg.secrets.username != "" && cfg.secrets.password != "") {
    # opnix will handle the secret retrieval
    # This module provides the interface for services to use
  };
}
