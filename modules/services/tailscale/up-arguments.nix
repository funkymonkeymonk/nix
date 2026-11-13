{lib}: cfg: authKeyFile:
lib.concatStringsSep " " (
  ["--auth-key=file:${authKeyFile}"]
  ++ lib.optionals cfg.exitNode ["--advertise-exit-node"]
  ++ lib.optionals (cfg.advertiseRoutes != []) ["--advertise-routes ${lib.concatStringsSep "," cfg.advertiseRoutes}"]
)
