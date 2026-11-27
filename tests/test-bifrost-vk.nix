{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  devenvConfig = import ../devenv.nix {inherit pkgs inputs;};
  genericTask = devenvConfig.tasks."secrets:create-bifrost-vk" or {};
  zeroTask = devenvConfig.tasks."secrets:create-bifrost-zero-vk" or {};
  genericTaskExec = genericTask.exec or "";
  zeroTaskExec = zeroTask.exec or "";
  taskValid =
    lib.attrByPath ["input" "confirm"] null genericTask == false
    && lib.attrByPath ["input" "keyName"] null genericTask == ""
    && lib.hasInfix "DEVENV_TASK_INPUT" genericTaskExec
    && lib.hasInfix "jq -e '.confirm == true'" genericTaskExec
    && lib.hasInfix "create-bifrost-vk.sh --key-name" genericTaskExec
    && lib.attrByPath ["input" "confirm"] null zeroTask == false
    && lib.hasInfix "create-bifrost-vk.sh --key-name Zero --confirm" zeroTaskExec;
  genericTaskExecScript = pkgs.writeText "bifrost-vk-task-exec.sh" (lib.replaceStrings ["${pkgs.openssl}/bin/openssl"] ["openssl"] genericTaskExec);
  zeroTaskExecScript = pkgs.writeText "bifrost-zero-vk-task-exec.sh" (lib.replaceStrings ["${pkgs.openssl}/bin/openssl"] ["openssl"] zeroTaskExec);
  creatorScript =
    if builtins.pathExists ../scripts/create-bifrost-vk.sh
    then ../scripts/create-bifrost-vk.sh
    else "";
in {
  bifrostVkCreation =
    pkgs.runCommand "test-bifrost-vk-creation" {
      nativeBuildInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnused pkgs.jq.bin];
    } ''
      BIFROST_VK_SCRIPT=${creatorScript} \
      BIFROST_VK_TASK_VALID=${lib.boolToString taskValid} \
      BIFROST_VK_GENERIC_TASK_EXEC_SCRIPT=${genericTaskExecScript} \
      BIFROST_VK_ZERO_TASK_EXEC_SCRIPT=${zeroTaskExecScript} \
      BIFROST_VK_BASH_BIN=${pkgs.bash}/bin/bash \
        ${pkgs.bash}/bin/bash ${./test-bifrost-vk.sh}
      touch $out
    '';
}
