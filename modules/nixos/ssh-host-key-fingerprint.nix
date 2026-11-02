{
  config,
  lib,
  ...
}: let
  cfg = config.services.openssh;
  hostName =
    if config.networking.hostName == null
    then "this NixOS machine"
    else config.networking.hostName;
  hostKeyPaths = map (key: key.path) cfg.hostKeys;
in {
  config = lib.mkIf cfg.enable {
    systemd.services.ssh-host-key-fingerprint = {
      description = "Display SSH host-key fingerprints on the local console";
      wantedBy = ["getty.target"];
      wants = lib.optionals cfg.generateHostKeys ["sshd-keygen.service"];
      after = lib.optionals cfg.generateHostKeys ["sshd-keygen.service"];
      before = ["getty@tty1.service"];
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        RemainAfterExit = true;
      };
      script = ''
        printf '\nSSH host-key fingerprints for %s:\n' ${lib.escapeShellArg hostName}
        found=0
        for host_key in ${lib.escapeShellArgs hostKeyPaths}; do
          if [ -r "$host_key" ]; then
            ${lib.getExe' cfg.package "ssh-keygen"} -lf "$host_key" || true
            found=1
          fi
        done
        if [ "$found" -eq 0 ]; then
          echo "No readable SSH host keys found."
        fi
      '';
    };
  };
}
