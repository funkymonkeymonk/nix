{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;

  nixosConfigs =
    if self == null
    then {}
    else lib.mapAttrs (_: nixos: nixos.config) self.nixosConfigurations;
  sshEnabledConfigs = lib.filterAttrs (_: config: config.services.openssh.enable or false) nixosConfigs;

  assertResult = name: condition:
    if condition
    then ''echo "  ${name}: OK"''
    else ''echo "  FAIL: ${name}"; failures=1'';

  checkMachine = name: config: let
    service = config.systemd.services.ssh-host-key-fingerprint or {};
    serviceConfig = service.serviceConfig or {};
    script = service.script or "";
    displayName =
      if config.networking.hostName == null
      then "NixOS"
      else config.networking.hostName;
    waitsForKeyGeneration =
      !(config.services.openssh.generateHostKeys or false)
      || ((builtins.elem "sshd-keygen.service" (service.after or []))
        && (builtins.elem "sshd-keygen.service" (service.wants or [])));
  in ''
    echo "Checking ${name}"
    ${assertResult "${name} displays its SSH host key fingerprint on the console" (lib.hasInfix "ssh-keygen" script && lib.hasInfix "SSH host-key fingerprints for %s" script && lib.hasInfix displayName script)}
    ${assertResult "${name} waits for generated host keys" waitsForKeyGeneration}
    ${assertResult "${name} prints before the tty1 login prompt" (builtins.elem "getty@tty1.service" (service.before or []) && builtins.elem "getty.target" (service.wantedBy or []))}
    ${assertResult "${name} sends fingerprint output to the console" ((serviceConfig.StandardOutput or null) == "journal+console")}
  '';
in {
  sshHostKeyFingerprint =
    if self == null
    then
      pkgs.runCommand "test-ssh-host-key-fingerprint-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else
      pkgs.runCommand "test-ssh-host-key-fingerprint" {} ''
        failures=0
        echo "=== Checking SSH host fingerprints are shown before NixOS login prompts ==="
        ${assertResult "NixOS machines with SSH are covered" (builtins.attrNames sshEnabledConfigs != [])}
        ${lib.concatStrings (lib.mapAttrsToList checkMachine sshEnabledConfigs)}
        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All SSH host-key fingerprint checks passed"
        touch $out
      '';
}
