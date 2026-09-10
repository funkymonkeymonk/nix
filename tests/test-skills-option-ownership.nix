{pkgs, ...}: let
  optionsSource = builtins.readFile ../modules/common/options.nix;
  roleSource = builtins.readFile ../modules/roles/agent-skills.nix;
  moved =
    pkgs.lib.hasInfix "options.myConfig.roles.agent-skills" roleSource
    && !(pkgs.lib.hasInfix "agent-skills = {" optionsSource);
in {
  skillsOptionOwnership = pkgs.runCommand "test-skills-option-ownership" {} ''
    echo "=== Testing agent-skills role option ownership ==="
    ${
      if moved
      then ''echo "  agent-skills.enable owned by agent-skills.nix: OK"''
      else ''echo "  FAIL: agent-skills.enable remains in common/options.nix"; exit 1''
    }
    touch $out
  '';
}
