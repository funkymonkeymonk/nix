{
  pkgs,
  inputs,
  ...
}: let
  scriptDirectory = ../scripts;
  devenv = import ../devenv.nix {inherit pkgs inputs;};
  scriptName = "machine-new";
  scriptExists = builtins.hasAttr scriptName devenv.scripts;
  script =
    if scriptExists
    then builtins.getAttr scriptName devenv.scripts
    else {};
  expectedScript = toString ../scripts/machine-scaffold.sh;
  hasGum = builtins.elem pkgs.gum devenv.packages;
  scriptUsesScaffold = toString (script.exec or "") == expectedScript;
  taskRemoved = !(builtins.hasAttr "machines:new" devenv.tasks);
  integrationFailures = builtins.filter (failure: failure != null) [
    (
      if scriptExists
      then null
      else "devenv does not expose the interactive machine-new script"
    )
    (
      if hasGum
      then null
      else "devenv packages do not include Gum"
    )
    (
      if scriptUsesScaffold
      then null
      else "machine-new must execute scripts/machine-scaffold.sh directly"
    )
    (
      if taskRemoved
      then null
      else "machines:new must not remain a task-runner entry point"
    )
  ];
  integrationTest =
    if integrationFailures == []
    then true
    else throw "machine-scaffold: devenv integration failed: ${pkgs.lib.concatStringsSep "; " integrationFailures}";
in {
  machineScaffold =
    pkgs.runCommand "test-machine-scaffold" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.nix];
    } ''
      ${
        if integrationTest
        then "echo 'machine-new devenv shell integration: OK'"
        else "exit 1"
      }
      MACHINE_SCAFFOLD_SCRIPT=${scriptDirectory}/machine-scaffold.sh \
        ${pkgs.bash}/bin/bash ${./test-machine-scaffold.sh}
      touch $out
    '';
}
