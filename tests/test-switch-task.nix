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

      # The shared helper provides non-interactive sudo for system tasks.
      grep -q 'runWithSudoPassword = ' "$devenv"
      grep -q 'run_with_sudo_password()' "$devenv"
      grep -q 'sudo -S' "$devenv"
      grep -q 'op read' "$devenv"

      # system:switch includes the shared helper in its task body.
      linux_task=$(sed -n '/"system:switch" = {/,/^[[:space:]]*};/p' "$devenv")
      grep -q 'runWithSudoPassword' <<< "$linux_task"

      touch "$out"
    '';
}
