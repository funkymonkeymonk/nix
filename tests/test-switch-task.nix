{pkgs, ...}: {
  switchTaskTest =
    pkgs.runCommand "test-switch-task" {
      devenv = ../devenv.nix;
      workspaceLib = ../modules/common/scripts/jj-workspace-lib;
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
      grep -q 'config.system.primaryUser' "$devenv"
      grep -Fq 'nix eval --impure --json "path:.#' "$devenv"
      grep -Fq 'nix eval --impure --raw "path:.#' "$devenv"
      [ "$(grep -c 'CONFIG_NAME=$(resolve_machine_config_name' "$devenv")" -eq 2 ]
      [ "$(grep -c 'PASSWORD_PATH=$(get_sudo_password_path' "$devenv")" -eq 2 ]

      # Custom unqualified sudo references resolve against the machine's default vault.
      grep -q 'resolve_sudo_password_ref()' "$devenv"
      grep -q 'op://.*default_vault' "$devenv"

      # system:switch includes the shared helper in its task body.
      linux_task=$(sed -n '/"system:switch" = {/,/^[[:space:]]*};/p' "$devenv")
      grep -q 'runWithSudoPassword' <<< "$linux_task"

      # The switch rebuild uses the immutable workspace commit; config and
      # sudo-reference lookups stay in the shared path-based helpers.
      grep -q 'source ./modules/common/scripts/jj-workspace-lib' <<< "$linux_task"
      grep -q 'FLAKE_REF=$(resolve_jj_flake_ref)' <<< "$linux_task"
      [ "$(grep -c '"\$FLAKE_REF#' <<< "$linux_task")" -eq 2 ]
      ! grep -Eq 'nix eval.*"?\.#' <<< "$linux_task"
      grep -Fq -- '--flake "$FLAKE_REF#$CONFIG_NAME"' <<< "$linux_task"
      grep -q 'export JJ_WORKSPACE_ROOT=' "$devenv"
      grep -q 'JJ_WORKSPACE_ROOT-' "$devenv"
      grep -q 'cd "\$JJ_REPO_ROOT"' "$devenv"
      grep -q 'resolve_jj_flake_ref()' "$workspaceLib"
      grep -q 'jj --ignore-working-copy --repository' "$workspaceLib"
      grep -q '?rev=' "$workspaceLib"

      touch "$out"
    '';
}
