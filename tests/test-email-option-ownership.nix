{pkgs, ...}: let
  optionsSource = builtins.readFile ../modules/common/options.nix;
  assistantSource = builtins.readFile ../modules/roles/assistant.nix;
  backupSource = builtins.readFile ../modules/roles/email-backup.nix;
  assistantMoved =
    pkgs.lib.hasInfix "options.myConfig.roles.assistant" assistantSource
    && !(pkgs.lib.hasInfix "assistant = {" optionsSource);
  backupMoved =
    pkgs.lib.hasInfix "options.myConfig.roles.email-backup" backupSource
    && !(pkgs.lib.hasInfix "email-backup = {" optionsSource);
in {
  emailOptionOwnership = pkgs.runCommand "test-email-option-ownership" {} ''
    echo "=== Testing email role option ownership ==="
    ${
      if assistantMoved
      then ''echo "  assistant.enable owned by assistant.nix: OK"''
      else ''echo "  FAIL: assistant.enable remains in common/options.nix"; exit 1''
    }
    ${
      if backupMoved
      then ''echo "  email-backup.enable owned by email-backup.nix: OK"''
      else ''echo "  FAIL: email-backup.enable remains in common/options.nix"; exit 1''
    }
    touch $out
  '';
}
