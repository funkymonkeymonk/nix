{
  config,
  lib,
  pkgs,
  ...
}: {
  home-manager.users = let
    cfg = config.myConfig.zellij;
  in
    lib.mkIf cfg.enable (
      lib.mapAttrs (_: user: {
        programs.zellij = {
          enable = true;
          settings = {
            theme = "dark";
            assumeUTF-8 = true;
          };
        };
      })
      config.home-manager.users
    );
}
