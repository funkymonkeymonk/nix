{
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs) lib;
  devenvConfig = import ../devenv.nix {inherit pkgs inputs;};
  task = devenvConfig.tasks."secrets:create-bifrost-setup-token" or {};
  taskExec = task.exec or "";
  taskValid =
    lib.attrByPath ["input" "confirm"] null task == false
    && lib.hasInfix "jq -e '.confirm == true'" taskExec
    && lib.hasInfix "create-bifrost-setup-token.sh --confirm" taskExec;
  taskExecScript = pkgs.writeText "bifrost-setup-token-task-exec.sh" (lib.replaceStrings ["${pkgs.openssl}/bin/openssl"] ["openssl"] taskExec);
  creatorScript =
    if builtins.pathExists ../scripts/create-bifrost-setup-token.sh
    then ../scripts/create-bifrost-setup-token.sh
    else "";
in {
  bifrostSetupToken =
    pkgs.runCommand "test-bifrost-setup-token" {
      nativeBuildInputs = [pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.jq.bin];
    } ''
      BIFROST_SETUP_SCRIPT=${creatorScript} \
      BIFROST_SETUP_TASK_VALID=${lib.boolToString taskValid} \
      BIFROST_SETUP_TASK_EXEC_SCRIPT=${taskExecScript} \
      BIFROST_SETUP_BASH_BIN=${pkgs.bash}/bin/bash \
        ${pkgs.bash}/bin/bash ${./test-bifrost-setup-token.sh}
      touch $out
    '';
}
