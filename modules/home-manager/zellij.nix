{
  config,
  lib,
  ...
}: {
  home-manager.users = let
    cfg = config.myConfig.zellij;
  in
    lib.mkIf cfg.enable (
      lib.mapAttrs (_: _user: {
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
