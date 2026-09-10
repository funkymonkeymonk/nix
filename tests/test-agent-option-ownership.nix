{pkgs, ...}: let
  optionsSource = builtins.readFile ../modules/common/options.nix;
  moduleSource = name: builtins.readFile (../modules/roles + "/${name}.nix");
  moved = name:
    pkgs.lib.hasInfix "options.myConfig.roles.${name}" (moduleSource name)
    && !(pkgs.lib.hasInfix "${name} = {" optionsSource);
  allMoved = builtins.all moved ["opencode" "claude" "pi"];
in {
  agentOptionOwnership = pkgs.runCommand "test-agent-option-ownership" {} ''
    echo "=== Testing agent role option ownership ==="
    ${
      if allMoved
      then ''echo "  opencode, claude, and pi toggles owned by their role modules: OK"''
      else ''echo "  FAIL: one or more agent role toggles remain in common/options.nix"; exit 1''
    }
    touch $out
  '';
}
