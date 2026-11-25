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
      ! grep -q 'agentsudo' <<< "$source"

      # The shared helper provides non-interactive sudo for system tasks.
      grep -q 'runWithSudoPassword = ' "$devenv"
      grep -q 'run_with_sudo_password()' "$devenv"
      grep -q 'sudo -S' "$devenv"
      grep -q 'op read' "$devenv"

      # Machine lookup and sudo reference resolution are shared by system tasks.
      grep -q 'resolve_machine_config_name()' "$devenv"
      grep -q 'get_sudo_password_path()' "$devenv"
      grep -q 'PRIMARY_USER=.*config.system.primaryUser' "$devenv"
      [ "$(grep -c 'CONFIG_NAME=$(resolve_machine_config_name' "$devenv")" -eq 2 ]
      [ "$(grep -c 'PASSWORD_PATH=$(get_sudo_password_path' "$devenv")" -eq 2 ]

      # Custom unqualified sudo references resolve against the machine's default vault.
      grep -q 'resolve_sudo_password_ref()' "$devenv"
      grep -q 'op://.*default_vault' "$devenv"

      # system:switch includes the shared helper in its task body.
      linux_task=$(sed -n '/"system:switch" = {/,/^[[:space:]]*};/p' "$devenv")
      grep -q 'runWithSudoPassword' <<< "$linux_task"

      touch "$out"
    '';
}
