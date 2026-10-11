{pkgs, ...}: let
  plugin = ../modules/home-manager/opencode/jj-workspace-access.js;
  test = ./test-jj-workspace-access.mjs;
in
  pkgs.runCommand "test-jj-workspace-access"
  {
    nativeBuildInputs = [pkgs.nodejs];
    JJ_WORKSPACE_PLUGIN = "${plugin}";
  }
  ''
    node --test ${test}
    touch $out
  ''
