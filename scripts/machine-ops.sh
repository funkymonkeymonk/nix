#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  machine-ops.sh info
  machine-ops.sh build <machine>
  machine-ops.sh check <machine>
  machine-ops.sh plan <machine>
  machine-ops.sh apply <machine> <plan-id>
  machine-ops.sh deploy <machine> [--use-machines-as-builders]
  machine-ops.sh deploy-auto <machine>
  machine-ops.sh install <machine>

All machine operations require one explicit catalog name. Remote operations
use that machine's catalog SecretSpec profile only for the requested command.
Set target.host in the ignored devenv.local.nix file for SSH endpoints.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  usage >&2
  exit 64
}

valid_machine_name() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]
}

valid_nix_system() {
  [[ "$1" =~ ^[A-Za-z0-9_]+-(linux|darwin)$ ]]
}

verified_plan_machine() {
  local requested_machine=$1
  local plan_id=$2
  local dotfile plan_dir plan_path plan_file plan_machine

  # Devenv 2.4 stores saved plans below DEVENV_DOTFILE/machine-plans/<id>.
  # The fallback matches Devenv's project-local default when run outside its shell.
  dotfile=${DEVENV_DOTFILE:-"$repo_root/.devenv"}
  plan_dir="$dotfile/machine-plans"
  plan_path="$plan_dir/$plan_id"
  plan_file="$plan_path/plan.json"
  [[ -d "$plan_dir" && ! -L "$plan_dir" && -d "$plan_path" && ! -L "$plan_path" && -f "$plan_file" && ! -L "$plan_file" ]] || {
    printf "ERROR: saved plan '%s' is missing from the project plan directory\n" "$plan_id" >&2
    exit 65
  }

  plan_machine=$(jq -er 'if type == "object" and (.machines | type == "object" and length == 1) then (.machines | keys[0]) else error("expected exactly one machine") end' "$plan_file" 2>/dev/null) || {
    printf "ERROR: saved plan '%s' is malformed or does not contain exactly one machine\n" "$plan_id" >&2
    exit 65
  }
  [[ "$plan_machine" == "$requested_machine" ]] || {
    printf "ERROR: saved plan '%s' targets machine '%s', not requested machine '%s'\n" "$plan_id" "$plan_machine" "$requested_machine" >&2
    exit 65
  }
  printf '%s' "$plan_machine"
}

resolve_devenv_bin() {
  if [[ -n "${DEVENV_BIN:-}" ]]; then
    printf '%s' "$DEVENV_BIN"
    return
  fi
  local nix_bin=${NIX_BIN:-nix}
  local store_path
  store_path=$("$nix_bin" build .#devenv --no-link --print-out-paths) || return 1
  printf '%s/bin/devenv' "$store_path"
}

machine_metadata() {
  local machine=$1
  local nix_bin=${NIX_BIN:-nix}
  local catalog_path="$repo_root/library/machines/catalog.nix"
  local expression

  # Machine names are restricted above before being interpolated into this
  # expression. Metadata is public catalog data; no SecretSpec provider is
  # loaded while resolving it.
  expression="let catalog = import ${catalog_path} { inputs = {}; }; machine = builtins.getAttr \"${machine}\" catalog; manifest = builtins.fromTOML (builtins.readFile ${repo_root}/secretspec.toml); profile = manifest.profiles.\${machine.secretProfile} or {}; hasSecrets = builtins.any (name: name != \"defaults\") (builtins.attrNames profile); hasBootstrapSecret = builtins.hasAttr \"OPNIX_SERVICE_ACCOUNT_TOKEN\" profile; in machine.secretProfile + \"\\t\" + (if machine.kind == \"nixos\" then \"nixos\" else \"darwin\") + \"\\t\" + (if hasSecrets then \"true\" else \"false\") + \"\\t\" + (if hasBootstrapSecret then \"true\" else \"false\") + \"\\t\" + machine.system"
  "$nix_bin" eval --impure --raw --expr "$expression"
}

run_scoped_machine_operation() {
  local operation=$1
  local machine=$2
  shift 2
  local metadata profile kind has_secrets has_bootstrap_secret devenv_bin secretspec_bin devenv_store_path

  metadata=$(machine_metadata "$machine") || {
    printf 'ERROR: machine %s is not in the catalog or has no deployment metadata\n' "$machine" >&2
    exit 64
  }
  IFS=$'\t' read -r profile kind has_secrets has_bootstrap_secret _target_system <<< "$metadata"
  case "$profile" in
    Homelab|Personal|MegamanX) ;;
    *) printf 'ERROR: unsupported SecretSpec profile for machine %s\n' "$machine" >&2; exit 64 ;;
  esac

  devenv_bin=$(resolve_devenv_bin) || {
    printf 'ERROR: unable to resolve the pinned devenv CLI for %s\n' "$operation" >&2
    exit 69
  }
  if [[ "$operation" == install && "$has_bootstrap_secret" != true ]]; then
    printf "ERROR: cannot install %s: profile '%s' must declare OPNIX_SERVICE_ACCOUNT_TOKEN with an approved default-vault reference before installing\n" "$machine" "$profile" >&2
    exit 69
  fi
  # Stock Devenv deploy does not consume SecretSpec values. In particular, it
  # cannot use MegamanX's sudo-password secret for activation, so do not resolve
  # an unused profile before starting its build/plan/apply flow.
  if [[ "$has_secrets" != true || "$operation" == deploy ]]; then
    "$devenv_bin" machines "$operation" "$@"
    return
  fi
  devenv_store_path=${devenv_bin%/bin/devenv}
  secretspec_bin=${SECRETSPEC_BIN:-$devenv_store_path/bin/secretspec}
  [[ -x "$secretspec_bin" ]] || {
    printf 'ERROR: SecretSpec CLI not found; refusing to run %s without its scoped profile\n' "$operation" >&2
    exit 69
  }
  "$secretspec_bin" run --profile "$profile" -- "$devenv_bin" machines "$operation" "$@"
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
operation=${1:-}
[[ -n "$operation" ]] || fail 'an operation is required'
shift

case "$operation" in
  info)
    [[ $# -eq 0 ]] || fail 'info does not accept a target'
    devenv_bin=$(resolve_devenv_bin) || fail 'unable to resolve the pinned devenv CLI'
    "$devenv_bin" machines info
    ;;
  build)
    [[ $# -eq 1 ]] || fail 'build requires exactly one machine name'
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    metadata=$(machine_metadata "$machine") || fail "unknown machine: $machine"
    IFS=$'\t' read -r _profile kind _has_secrets _has_bootstrap_secret _target_system <<< "$metadata"
    case "$kind" in
      nixos) build_role=nixos ;;
      darwin) build_role=nix-darwin ;;
      *) fail "machine $machine has an unsupported build role" ;;
    esac
    devenv_bin=$(resolve_devenv_bin) || fail 'unable to resolve the pinned devenv CLI'
    "$devenv_bin" build "machines.${machine}.build.${build_role}"
    ;;
  check|plan)
    [[ $# -eq 1 ]] || fail "$operation requires exactly one machine name"
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    run_scoped_machine_operation "$operation" "$machine" "$machine"
    ;;
  deploy)
    [[ $# -eq 1 || $# -eq 2 ]] || fail 'deploy requires one machine name and an optional builder flag'
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    if [[ $# -eq 2 ]]; then
      [[ "$2" == --use-machines-as-builders ]] || fail "unsupported deploy option: $2"
      run_scoped_machine_operation deploy "$machine" --use-machines-as-builders "$machine"
    else
      run_scoped_machine_operation deploy "$machine" "$machine"
    fi
    ;;
  deploy-auto)
    [[ $# -eq 1 ]] || fail 'deploy-auto requires exactly one machine name'
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    metadata=$(machine_metadata "$machine") || fail "unknown machine: $machine"
    IFS=$'\t' read -r _profile _kind _has_secrets _has_bootstrap_secret target_system <<< "$metadata"
    nix_bin=${NIX_BIN:-nix}
    current_system=$("$nix_bin" eval --impure --raw --expr 'builtins.currentSystem') || {
      printf 'ERROR: unable to determine the current Nix system\n' >&2
      exit 69
    }
    if ! valid_nix_system "$current_system" || ! valid_nix_system "$target_system"; then
      printf 'ERROR: invalid current or target Nix system identifier\n' >&2
      exit 69
    fi
    if [[ "$current_system" == "$target_system" ]]; then
      printf 'Nix system matches (%s); deploying with the local builder.\n' "$current_system"
      run_scoped_machine_operation deploy "$machine" "$machine"
    else
      printf 'Nix system differs (%s -> %s); asking Devenv to use matching machine builders.\n' "$current_system" "$target_system"
      run_scoped_machine_operation deploy "$machine" --use-machines-as-builders "$machine"
    fi
    ;;
  apply)
    [[ $# -eq 2 ]] || fail 'apply requires an explicit machine name and plan ID'
    machine=$1
    plan_id=$2
    valid_machine_name "$machine" || fail 'machine name is malformed'
    [[ "$plan_id" =~ ^plan-[A-Za-z0-9-]+$ ]] || fail 'plan ID is malformed'
    machine=$(verified_plan_machine "$machine" "$plan_id")
    run_scoped_machine_operation apply "$machine" "$plan_id"
    ;;
  install)
    [[ $# -eq 1 ]] || fail 'install requires exactly one machine name'
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    printf 'WARNING: installing %s may erase or destroy data on the target disk.\n' "$machine" >&2
    printf 'Type yes to continue; anything else cancels: ' >&2
    answer=''
    IFS= read -r answer || {
      printf '\nInstallation cancelled.\n' >&2
      exit 1
    }
    [[ "$answer" == yes ]] || {
      printf 'Installation cancelled.\n' >&2
      exit 1
    }
    run_scoped_machine_operation install "$machine" "$machine"
    ;;
  *)
    fail "unknown operation: $operation"
    ;;
esac
