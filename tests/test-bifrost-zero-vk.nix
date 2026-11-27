{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  devenvConfig = import ../devenv.nix {inherit pkgs inputs;};
  task = devenvConfig.tasks."secrets:create-bifrost-zero-vk" or {};
  taskExec = task.exec or "";
  taskExecScript = pkgs.writeText "bifrost-zero-vk-task-exec.sh" taskExec;
  taskValid =
    lib.attrByPath ["input" "confirm"] null task
    == false
    && lib.hasInfix "DEVENV_TASK_INPUT" taskExec
    && lib.hasInfix "jq -e '.confirm == true'" taskExec
    && lib.hasInfix "create-bifrost-zero-vk.sh --confirm" taskExec;
  creatorScript =
    if builtins.pathExists ../scripts/create-bifrost-zero-vk.sh
    then ../scripts/create-bifrost-zero-vk.sh
    else "";
in {
  bifrostZeroVkCreation =
    pkgs.runCommand "test-bifrost-zero-vk-creation" {
      nativeBuildInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.jq.bin];
    } ''
      BIFROST_VK_SCRIPT=${creatorScript} \
      BIFROST_VK_TASK_VALID=${lib.boolToString taskValid} \
      BIFROST_VK_TASK_EXEC_SCRIPT=${taskExecScript} \
      BIFROST_VK_BASH_BIN=${pkgs.bash}/bin/bash \
        ${pkgs.bash}/bin/bash ${./test-bifrost-zero-vk.sh}
      touch $out
    '';
}
