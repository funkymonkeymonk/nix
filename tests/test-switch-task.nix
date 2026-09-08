{pkgs, ...}: {
  switchTaskTest =
    pkgs.runCommand "test-switch-task" {
      devenv = ../devenv.nix;
    } ''
      source=$(cat "$devenv")

      # The supported task entry point is namespaced; the shell function exposes
      # the short `switch` command after entering devenv.
      grep -q '"system:switch" = {' <<< "$source"
      grep -q 'switch() {.*system:switch' <<< "$source"
      grep -q 'command devenv tasks run system:switch' <<< "$source"

      # NixOS runs from devenv without an interactive sudo prompt.
      linux_task=$(sed -n '/"system:switch" = {/,/^[[:space:]]*};/p' "$devenv")
      grep -q 'sudo -S' <<< "$linux_task"
      grep -q 'op read' <<< "$linux_task"

      touch "$out"
    '';
}
