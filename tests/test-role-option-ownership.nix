{pkgs, ...}: let
  optionsSource = builtins.readFile ../modules/common/options.nix;
  moduleSource = name: builtins.readFile (../modules/roles + "/${name}.nix");
  moved = name:
    pkgs.lib.hasInfix "options.myConfig.roles.${name}" (moduleSource name)
    && !(pkgs.lib.hasInfix "${name} = {" optionsSource);
  # The 9 roles that were previously declared in the central options file.
  centralRoles = [
    "foundation"
    "developer"
    "creative"
    "gaming"
    "desktop"
    "workstation"
    "work"
    "entertainment"
    "homebrew"
  ];
  allMoved = builtins.all moved centralRoles;
in {
  roleOptionOwnership = pkgs.runCommand "test-role-option-ownership" {} ''
    echo "=== Testing central role option ownership ==="
    ${
      if allMoved
      then ''echo "  all 9 central role toggles owned by their role modules: OK"''
      else ''echo "  FAIL: one or more central role toggles remain in common/options.nix"; exit 1''
    }
    touch $out
  '';
}
