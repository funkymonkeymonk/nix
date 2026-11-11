{
  pkgs,
  inputs,
  ...
}: let
  scriptDirectory = ../scripts;
  devenv = import ../devenv.nix {inherit pkgs inputs;};
  taskName = "machines:new";
  taskExists = builtins.hasAttr taskName devenv.tasks;
  task =
    if taskExists
    then builtins.getAttr taskName devenv.tasks
    else {};
  expectedTaskExec = "exec ./scripts/machine-scaffold.sh";
  hasGum = builtins.elem pkgs.gum devenv.packages;
  taskUsesRepoRootScript = task.exec or "" == expectedTaskExec;
  taskHasNoTargetInput = !(task ? input);
  taskHasNoImplicitDependencies = !(task ? after);
  integrationFailures = builtins.filter (failure: failure != null) [
    (
      if taskExists
      then null
      else "devenv does not expose machines:new"
    )
    (
      if hasGum
      then null
      else "devenv packages do not include Gum"
    )
    (
      if taskUsesRepoRootScript
      then null
      else "machines:new must execute only ./scripts/machine-scaffold.sh from the repository root"
    )
    (
      if taskHasNoTargetInput
      then null
      else "machines:new must not require a machine target input"
    )
    (
      if taskHasNoImplicitDependencies
      then null
      else "machines:new must not chain other operations through task dependencies"
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
        then "echo 'machines:new devenv integration: OK'"
        else "exit 1"
      }
      MACHINE_SCAFFOLD_SCRIPT=${scriptDirectory}/machine-scaffold.sh \
        ${pkgs.bash}/bin/bash ${./test-machine-scaffold.sh}
      touch $out
    '';
}
