{...}: rec {
  darwinUserEnv = config: let
    user =
      if config.myConfig.users != []
      then (builtins.head config.myConfig.users).name
      else "root";
  in {
    name = user;
    home = "/Users/${user}";
  };

  primaryUser = config: (darwinUserEnv config).name;
  darwinHomeDir = config: (darwinUserEnv config).home;
}
