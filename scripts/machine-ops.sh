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
  expression="let catalog = import ${catalog_path} { inputs = {}; }; machine = builtins.getAttr \"${machine}\" catalog; manifest = builtins.fromTOML (builtins.readFile ${repo_root}/secretspec.toml); profile = manifest.profiles.\${machine.secretProfile} or {}; tailscale = (machine.overrides or {}).tailscale or {}; hasSecrets = builtins.any (name: name != \"defaults\") (builtins.attrNames profile); hasBootstrapSecret = builtins.hasAttr \"OPNIX_SERVICE_ACCOUNT_TOKEN\" profile; hasTailscaleOAuth = builtins.hasAttr \"TAILSCALE_OAUTH_CLIENT_ID\" profile && builtins.hasAttr \"TAILSCALE_OAUTH_CLIENT_SECRET\" profile; in machine.secretProfile + \"\\t\" + (if machine.kind == \"nixos\" then \"nixos\" else \"darwin\") + \"\\t\" + (if hasSecrets then \"true\" else \"false\") + \"\\t\" + (if hasBootstrapSecret then \"true\" else \"false\") + \"\\t\" + machine.system + \"\\t\" + (builtins.toJSON (tailscale.enable or false)) + \"\\t\" + (if hasTailscaleOAuth then \"true\" else \"false\") + \"\\t\" + builtins.toJSON (tailscale.authKeyTags or [])"
  "$nix_bin" eval --impure --raw --expr "$expression"
}

megamanx_builder_metadata() {
  local nix_bin=${NIX_BIN:-nix}
  local flake_ref="path:$repo_root"
  local expression

  expression="let
    zero = (builtins.getFlake \"$flake_ref\").nixosConfigurations.zero.config;
    builders = builtins.filter (builder: builder.hostName == \"megamanx\") zero.nix.buildMachines;
  in builtins.toJSON {
    builders = map (builder: {
      inherit (builder) hostName system protocol sshUser publicHostKey;
    }) builders;
    defaultVault = zero.myConfig.onepassword.defaultVault;
    keyReference = zero.myConfig.onepassword.secrets.nixRemoteBuilderKey.reference;
  }"
  "$nix_bin" eval --impure --raw --expr "$expression"
}

build_with_megamanx() {
  local devenv_bin=$1
  local build_attribute=$2
  local builder_json builder_count builder host_name builder_system protocol ssh_user public_host_key
  local default_vault key_reference key_uri old_umask encoded_ssh_key encoded_host_key store_uri
  local nix_bin=${NIX_BIN:-nix}

  builder_json=$(megamanx_builder_metadata) || {
    printf 'ERROR: unable to evaluate the canonical MegamanX remote builder configuration\n' >&2
    exit 69
  }
  builder_count=$(jq -er 'if (.builders | type) == "array" then (.builders | length) else error("builders must be an array") end' <<< "$builder_json") || {
    printf 'ERROR: canonical MegamanX builder metadata is malformed\n' >&2
    exit 69
  }
  [[ "$builder_count" == 1 ]] || {
    printf 'ERROR: expected exactly one configured MegamanX remote builder, found %s\n' "$builder_count" >&2
    exit 69
  }
  builder=$(jq -ce '.builders[0]' <<< "$builder_json") || {
    printf 'ERROR: canonical MegamanX builder metadata is malformed\n' >&2
    exit 69
  }
  host_name=$(jq -er '.hostName | select(type == "string" and length > 0)' <<< "$builder") || exit 69
  builder_system=$(jq -er '.system | select(type == "string" and length > 0)' <<< "$builder") || exit 69
  protocol=$(jq -er '.protocol | select(type == "string" and length > 0)' <<< "$builder") || exit 69
  ssh_user=$(jq -er '.sshUser | select(type == "string" and length > 0)' <<< "$builder") || exit 69
  public_host_key=$(jq -er '.publicHostKey | select(type == "string" and test("^[A-Za-z0-9+/]+=*$"))' <<< "$builder") || exit 69
  default_vault=$(jq -er '.defaultVault | select(type == "string" and length > 0 and (contains("/") | not) and (contains("\n") | not))' <<< "$builder_json") || exit 69
  key_reference=$(jq -er '.keyReference | select(type == "string" and length > 0) | select(startswith("op://") | not)' <<< "$builder_json") || exit 69

  [[ "$host_name" == megamanx && "$builder_system" == aarch64-darwin && "$protocol" == ssh-ng && "$ssh_user" == nixbuilder ]] || {
    printf 'ERROR: configured MegamanX builder does not match the supported aarch64-darwin ssh-ng target\n' >&2
    exit 69
  }
  [[ "$key_reference" != /* && "$key_reference" != *$'\n'* ]] || {
    printf 'ERROR: configured MegamanX builder key reference must be an unqualified Item/field reference\n' >&2
    exit 69
  }
  command -v "$nix_bin" >/dev/null 2>&1 || {
    printf 'ERROR: Nix CLI not found while preparing the MegamanX remote build\n' >&2
    exit 69
  }
  command -v op >/dev/null 2>&1 || {
    printf 'ERROR: 1Password CLI (op) is required for a MegamanX remote build\n' >&2
    exit 69
  }

  key_uri="op://$default_vault/$key_reference"
  old_umask=$(umask)
  umask 077
  BUILDER_KEY_FILE=$(mktemp "${TMPDIR:-/tmp}/nix-remote-builder.XXXXXX") || {
    umask "$old_umask"
    printf 'ERROR: unable to create a temporary MegamanX builder key file\n' >&2
    exit 69
  }
  umask "$old_umask"
  chmod 0600 "$BUILDER_KEY_FILE" || {
    printf 'ERROR: unable to secure the temporary MegamanX builder key file\n' >&2
    exit 69
  }
  if ! op read "$key_uri" > "$BUILDER_KEY_FILE"; then
    printf 'ERROR: failed to read the MegamanX remote builder key from 1Password\n' >&2
    exit 69
  fi
  [[ -s "$BUILDER_KEY_FILE" ]] || {
    printf 'ERROR: 1Password returned an empty MegamanX remote builder key\n' >&2
    exit 69
  }

  encoded_ssh_key=$(jq -rn --arg value "$BUILDER_KEY_FILE" '$value | @uri') || exit 69
  encoded_host_key=$(jq -rn --arg value "$public_host_key" '$value | @uri') || exit 69
  store_uri="$protocol://$ssh_user@$host_name?ssh-key=$encoded_ssh_key&base64-ssh-public-host-key=$encoded_host_key"
  "$devenv_bin" build "$build_attribute" \
    --nix-option store "$store_uri" \
    --nix-option max-jobs 0
}

machine_target_host() {
  local machine=$1
  local devenv_bin=$2
  local info target_host

  info=$(NO_COLOR=1 "$devenv_bin" machines info "$machine") || {
    printf 'ERROR: unable to resolve the deployment target for %s\n' "$machine" >&2
    return 69
  }
  target_host=$(printf '%s\n' "$info" \
    | sed -E $'s/\\x1B\\[[0-9;]*[[:alpha:]]//g' \
    | awk -F'|' -v expected="$machine" '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      NF >= 4 && trim($2) == expected { print trim($4); found = 1; exit }
      END { if (!found) exit 1 }
    ') || {
    printf 'ERROR: machine info did not provide a target host for %s\n' "$machine" >&2
    return 69
  }
  [[ -n "$target_host" ]] || {
    printf 'ERROR: machine info returned an empty target host for %s\n' "$machine" >&2
    return 69
  }
  printf '%s' "$target_host"
}

TAILSCALE_CLEANUP_TARGET=""
TAILSCALE_CLEANUP_SSH=""
TAILSCALE_CLEANUP_COMMAND=""
BUILDER_KEY_FILE=""

cleanup_staged_tailscale_key() {
  [[ -n "$TAILSCALE_CLEANUP_TARGET" ]] || return 0
  if ! "$TAILSCALE_CLEANUP_SSH" -o BatchMode=yes -o StrictHostKeyChecking=yes \
      "$TAILSCALE_CLEANUP_TARGET" "$TAILSCALE_CLEANUP_COMMAND" >/dev/null 2>&1; then
    printf 'WARNING: unable to remove the temporary Tailscale auth-key file from the named target\n' >&2
  fi
  TAILSCALE_CLEANUP_TARGET=""
  TAILSCALE_CLEANUP_SSH=""
  TAILSCALE_CLEANUP_COMMAND=""
}

cleanup_builder_key() {
  [[ -n "$BUILDER_KEY_FILE" ]] || return 0
  rm -f "$BUILDER_KEY_FILE"
  BUILDER_KEY_FILE=""
}

cleanup_machine_ops_artifacts() {
  cleanup_staged_tailscale_key
  cleanup_builder_key
}
trap cleanup_machine_ops_artifacts EXIT

tailscale_backend_state() {
  local target_host=$1
  local ssh_bin=$2
  local jq_bin=$3
  local status_json

  status_json=$("$ssh_bin" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target_host" \
    '/run/current-system/sw/bin/tailscale status --json 2>/dev/null') || return 1
  printf '%s' "$status_json" \
    | "$jq_bin" -er '.BackendState | select(type == "string" and length > 0)' 2>/dev/null
}

stage_tailscale_auth_key() {
  local target_kind=$1
  local target_host=$2
  local ssh_bin=$3
  local auth_key=$4
  local stage_command cleanup_command

  case "$target_kind" in
    nixos)
      stage_command='set -eu; umask 077; mkdir -p /run/devenv; chmod 0700 /run/devenv; cat > /run/devenv/tailscale-auth-key; chmod 0600 /run/devenv/tailscale-auth-key'
      cleanup_command='rm -f -- /run/devenv/tailscale-auth-key'
      ;;
    darwin)
      stage_command="set -eu; umask 077; tmp=\$(mktemp /tmp/devenv-tailscale-auth-key.XXXXXX); trap 'rm -f -- \"\$tmp\"' EXIT; cat > \"\$tmp\"; chmod 0600 \"\$tmp\"; mv -f -- \"\$tmp\" /tmp/devenv-tailscale-auth-key; trap - EXIT"
      cleanup_command='rm -f -- /tmp/devenv-tailscale-auth-key'
      ;;
    *)
      printf 'ERROR: unsupported Tailscale target platform: %s\n' "$target_kind" >&2
      return 1
      ;;
  esac

  if ! printf '%s' "$auth_key" \
      | "$ssh_bin" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target_host" "$stage_command"; then
    unset auth_key
    "$ssh_bin" -o BatchMode=yes -o StrictHostKeyChecking=yes "$target_host" "$cleanup_command" >/dev/null 2>&1 || true
    return 1
  fi
  unset auth_key

  TAILSCALE_CLEANUP_TARGET=$target_host
  TAILSCALE_CLEANUP_SSH=$ssh_bin
  TAILSCALE_CLEANUP_COMMAND=$cleanup_command
}

wait_for_tailscale_running() {
  local target_host=$1
  local ssh_bin=$2
  local jq_bin=$3
  local backend_state

  for ((attempt = 1; attempt <= 30; attempt += 1)); do
    if backend_state=$(tailscale_backend_state "$target_host" "$ssh_bin" "$jq_bin") \
        && [[ "$backend_state" == Running ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

run_scoped_machine_operation() {
  local operation=$1
  local machine=$2
  shift 2
  local metadata profile kind has_secrets has_bootstrap_secret target_system tailscale_enabled has_tailscale_oauth tailscale_auth_tags
  local devenv_bin secretspec_bin devenv_store_path

  metadata=$(machine_metadata "$machine") || {
    printf 'ERROR: machine %s is not in the catalog or has no deployment metadata\n' "$machine" >&2
    exit 64
  }
  IFS=$'\t' read -r profile kind has_secrets has_bootstrap_secret target_system tailscale_enabled has_tailscale_oauth tailscale_auth_tags <<< "$metadata"
  case "$profile" in
    Opnix|Personal|MegamanX|Employee) ;;
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
  if [[ "$operation" == install ]]; then
    # Devenv's install.secrets resolver writes this token to the target after
    # nixos-install, without putting the value in the Nix store.
    "$devenv_bin" machines install "$@" --secretspec-profile "$profile"
    return
  fi
  if [[ ( "$operation" == deploy || "$operation" == apply ) && "$tailscale_enabled" == true ]]; then
    local target_host ssh_bin jq_bin backend_state tailscale_auth_key authkey_script key_staged=false deploy_status=0
    local tailscale_auth_tags_array
    target_host=$(machine_target_host "$machine" "$devenv_bin") || exit $?
    ssh_bin=${SSH_BIN:-ssh}
    jq_bin=${JQ_BIN:-jq}
    if ! backend_state=$(tailscale_backend_state "$target_host" "$ssh_bin" "$jq_bin"); then
      printf 'ERROR: unable to inspect a valid Tailscale backend state on %s; refusing OAuth enrollment\n' "$machine" >&2
      exit 69
    fi

    case "$backend_state" in
      Running)
        ;;
      NeedsLogin)
      [[ "$has_tailscale_oauth" == true ]] || {
        printf 'ERROR: %s uses OAuth-generated Tailscale keys but its SecretSpec profile lacks the OAuth client ID and secret\n' "$machine" >&2
        exit 69
      }
      devenv_store_path=${devenv_bin%/bin/devenv}
      secretspec_bin=${SECRETSPEC_BIN:-$devenv_store_path/bin/secretspec}
      [[ -x "$secretspec_bin" ]] || {
        printf 'ERROR: SecretSpec CLI not found; refusing to generate a Tailscale auth key without its scoped profile\n' >&2
        exit 69
      }
      authkey_script=${TAILSCALE_AUTHKEY_SCRIPT:-"$repo_root/scripts/tailscale-oauth-authkey.sh"}
      [[ -x "$authkey_script" ]] || {
        printf 'ERROR: Tailscale OAuth auth-key helper is not executable: %s\n' "$authkey_script" >&2
        exit 69
      }
      tailscale_auth_tags_array=$(printf '%s' "$tailscale_auth_tags" | "$jq_bin" -e 'type == "array" and length > 0' >/dev/null && printf '%s' "$tailscale_auth_tags") || {
        printf 'ERROR: %s has no configured Tailscale OAuth tags\n' "$machine" >&2
        exit 69
      }
      tailscale_auth_key=$("$secretspec_bin" run --profile "$profile" -- "$authkey_script" "$machine" "$tailscale_auth_tags_array") || {
        printf 'ERROR: could not generate a one-time Tailscale auth key for %s\n' "$machine" >&2
        exit 69
      }
      [[ -n "$tailscale_auth_key" ]] || {
        printf 'ERROR: Tailscale OAuth helper returned an empty auth key for %s\n' "$machine" >&2
        exit 69
      }
        if ! stage_tailscale_auth_key "$kind" "$target_host" "$ssh_bin" "$tailscale_auth_key"; then
          unset tailscale_auth_key
          printf 'ERROR: failed to stage the one-time Tailscale auth key on %s\n' "$machine" >&2
          exit 69
        fi
        unset tailscale_auth_key
        key_staged=true
        ;;
      *)
        printf 'ERROR: Tailscale backend state on %s is unsupported (%s); refusing OAuth enrollment\n' "$machine" "$backend_state" >&2
        exit 69
        ;;
    esac

    devenv_store_path=${devenv_bin%/bin/devenv}
    secretspec_bin=${SECRETSPEC_BIN:-$devenv_store_path/bin/secretspec}
    if [[ "$operation" == apply && "$has_secrets" == true ]]; then
      [[ -x "$secretspec_bin" ]] || {
        printf 'ERROR: SecretSpec CLI not found; refusing to apply %s without its scoped profile\n' "$machine" >&2
        exit 69
      }
      if "$secretspec_bin" run --profile "$profile" -- "$devenv_bin" machines "$operation" "$@"; then
        deploy_status=0
      else
        deploy_status=$?
      fi
    elif "$devenv_bin" machines "$operation" "$@"; then
      deploy_status=0
    else
      deploy_status=$?
    fi

    if [[ "$key_staged" == true && "$deploy_status" -eq 0 ]]; then
      if ! wait_for_tailscale_running "$target_host" "$ssh_bin" "$jq_bin"; then
        printf 'ERROR: %s did not reach Tailscale BackendState=Running after activation\n' "$machine" >&2
        deploy_status=69
      fi
    fi
    if [[ "$key_staged" == true ]]; then
      cleanup_staged_tailscale_key
    fi
    return "$deploy_status"
  fi

  # Stock Devenv deploy does not consume SecretSpec values for ordinary
  # machines, so do not resolve an unused profile before its build/plan/apply.
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
    IFS=$'\t' read -r _profile kind _has_secrets _has_bootstrap_secret target_system _tailscale_enabled _has_tailscale_oauth _tailscale_auth_tags <<< "$metadata"
    case "$kind" in
      nixos) build_role=nixos ;;
      darwin) build_role=nix-darwin ;;
      *) fail "machine $machine has an unsupported build role" ;;
    esac
    devenv_bin=$(resolve_devenv_bin) || fail 'unable to resolve the pinned devenv CLI'
    nix_bin=${NIX_BIN:-nix}
    current_system=$("$nix_bin" eval --impure --raw --expr 'builtins.currentSystem') || {
      printf 'ERROR: unable to determine the current Nix system for machine build\n' >&2
      exit 69
    }
    valid_nix_system "$current_system" && valid_nix_system "$target_system" || {
      printf 'ERROR: invalid current or target Nix system for machine build\n' >&2
      exit 69
    }
    build_attribute="machines.${machine}.build.${build_role}"
    if [[ "$current_system" == "$target_system" ]]; then
      "$devenv_bin" build "$build_attribute"
    elif [[ "$target_system" == aarch64-darwin ]]; then
      build_with_megamanx "$devenv_bin" "$build_attribute"
    else
      printf 'ERROR: no compatible remote builder is configured for cross target %s (%s -> %s)\n' "$machine" "$current_system" "$target_system" >&2
      exit 69
    fi
    ;;
  check|plan)
    [[ $# -eq 1 ]] || fail "$operation requires exactly one machine name"
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    run_scoped_machine_operation "$operation" "$machine" "$machine"
    ;;
  deploy)
    [[ $# -ge 1 ]] || fail 'deploy requires one machine name'
    machine=$1
    shift
    valid_machine_name "$machine" || fail 'machine name is malformed'
    deploy_options=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --use-machines-as-builders|--yes) deploy_options+=("$1") ;;
        *) fail "unsupported deploy option: $1" ;;
      esac
      shift
    done
    run_scoped_machine_operation deploy "$machine" "${deploy_options[@]}" "$machine"
    ;;
  deploy-auto)
    [[ $# -eq 1 ]] || fail 'deploy-auto requires exactly one machine name'
    machine=$1
    valid_machine_name "$machine" || fail 'machine name is malformed'
    metadata=$(machine_metadata "$machine") || fail "unknown machine: $machine"
    IFS=$'\t' read -r _profile _kind _has_secrets _has_bootstrap_secret target_system _tailscale_enabled _has_tailscale_oauth _tailscale_auth_tags <<< "$metadata"
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
