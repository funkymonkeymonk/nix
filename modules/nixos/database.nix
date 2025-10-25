{pkgs, ...}: {
  # PostgreSQL database server
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_15;
    ensureDatabases = ["linkwarden"];
    ensureUsers = [
      {
        name = "linkwarden";
        ensureDBOwnership = true;
      }
    ];
    authentication = ''
      local linkwarden linkwarden trust
    '';
  };
}
