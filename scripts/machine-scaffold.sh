#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'machine scaffold: %s\n' "$*" >&2
  exit 1
}

# Render a safe Nix double-quoted string literal. All prompted strings pass
# through this helper before being emitted into either generated Nix file.
nix_string() {
  local value=$1 escaped='' character index
  for ((index = 0; index < ${#value}; index++)); do
    character=${value:index:1}
    case "$character" in
      \\) escaped+="\\\\" ;;
      '"') escaped+='\"' ;;
      '$') escaped+='\$' ;;
      $'\n') escaped+='\n' ;;
      $'\r') escaped+='\r' ;;
      $'\t') escaped+='\t' ;;
      *) escaped+=$character ;;
    esac
  done
  printf '"%s"' "$escaped"
}

is_nonempty_text() {
  local label=$1 value=$2
  if [[ -z ${value//[[:space:]]/} ]]; then
    fail "$label is required and cannot be empty"
  fi
  if [[ $value =~ [[:cntrl:]] ]]; then
    fail "$label contains unsupported control characters"
  fi
}

root_override=${MACHINE_SCAFFOLD_ROOT:-}
if [[ -n $root_override ]]; then
  [[ -d $root_override ]] || fail "repository root does not exist: $root_override"
  repo_root=$(cd -- "$root_override" && pwd -P)
else
  repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
  if [[ ! -t 0 || ! -t 1 ]]; then
    fail "interactive terminal input and output are required; run this task from a terminal"
  fi
fi

catalog_file="$repo_root/library/machines/catalog.nix"
options_file="$repo_root/library/machines/wizard-options.nix"
secretspec_file="$repo_root/secretspec.toml"
[[ -f $catalog_file ]] || fail "expected machine catalog is missing: $catalog_file"
[[ -f $options_file ]] || fail "machine wizard option manifest is missing: $options_file"
[[ -f $secretspec_file ]] || fail "SecretSpec configuration is missing: $secretspec_file"
[[ -d $repo_root/machines ]] || fail "expected machines directory is missing under $repo_root"

if [[ -n ${GUM_BIN:-} ]]; then
  gum_bin=$GUM_BIN
else
  gum_bin=gum
fi
command -v "$gum_bin" >/dev/null 2>&1 || fail "Gum was not found; install gum or add it to PATH"

machine_destination=
catalog_destination=
generated_dir="$repo_root/library/machines/generated"
temporary_dir=
machine_created=0
catalog_created=0
generated_dir_created=0
generation_succeeded=0
cleanup() {
  local status=$?
  if ((generation_succeeded == 0)); then
    if ((catalog_created == 1)); then
      rm -f -- "$catalog_destination"
    fi
    if ((machine_created == 1)); then
      rm -rf -- "$machine_destination"
    fi
    if ((generated_dir_created == 1)); then
      rmdir -- "$generated_dir" 2>/dev/null || true
    fi
  fi
  if [[ -n $temporary_dir ]]; then
    rm -rf -- "$temporary_dir"
  fi
  return "$status"
}
trap cleanup EXIT

cancelled=0
prompt_result=
prompt() {
  local output status
  if output=$("$gum_bin" "$@"); then
    prompt_result=$output
    return 0
  else
    status=$?
    if ((status == 130)); then
      cancelled=1
      return 1
    fi
    fail "Gum prompt '$1' failed with exit status $status"
  fi
}
handle_prompt_failure() {
  if ((cancelled == 1)); then
    exit 0
  fi
  exit 1
}

# Nix supplies the manifest data so the checked-in option file remains the
# source of truth for compatible archetypes and roles.
manifest_nix=$(nix_string "$options_file")
catalog_nix=$(nix_string "$catalog_file")
read_manifest_archetypes() {
  local platform=$1 platform_nix expression
  platform_nix=$(nix_string "$platform")
  expression="let manifest = import $manifest_nix; in builtins.concatStringsSep \"\\n\" (map (choice: builtins.concatStringsSep \"\\t\" [choice.label choice.kind choice.module]) manifest.$platform_nix.archetypes)"
  nix eval --impure --raw --expr "$expression"
}
read_manifest_roles() {
  local platform=$1 platform_nix expression
  platform_nix=$(nix_string "$platform")
  expression="let manifest = import $manifest_nix; in builtins.concatStringsSep \"\\n\" manifest.$platform_nix.roles"
  nix eval --impure --raw --expr "$expression"
}
read_catalog_names() {
  local expression
  expression="let catalog = (import $catalog_nix) { inputs = {}; }; in builtins.concatStringsSep \"\\n\" (builtins.attrNames catalog)"
  nix eval --impure --raw --expr "$expression"
}
read_catalog_host_collisions() {
  local hostname=$1 hostname_nix expression
  hostname_nix=$(nix_string "$hostname")
  expression="let catalog = (import $catalog_nix) { inputs = {}; }; in builtins.concatStringsSep \"\\n\" (builtins.filter (name: ((builtins.getAttr name catalog).hostname or null) == $hostname_nix) (builtins.attrNames catalog))"
  nix eval --impure --raw --expr "$expression"
}

# SecretSpec profile names are section headers only; no secret values are read.
profiles=()
while IFS= read -r profile; do
  [[ -n $profile ]] && profiles+=("$profile")
done < <(awk '
  /^\[profiles\.[^]]+\]$/ {
    profile = $0
    sub(/^\[profiles\./, "", profile)
    sub(/\]$/, "", profile)
    if (profile !~ /\./) print profile
  }
' "$secretspec_file")
(( ${#profiles[@]} > 0 )) || fail "no SecretSpec profiles are configured in $secretspec_file"

if ! prompt choose 'darwin' 'nixos'; then
  handle_prompt_failure
fi
target_kind=$prompt_result
case "$target_kind" in
  darwin)
    supported_platforms=(aarch64-darwin)
    ;;
  nixos)
    supported_platforms=(x86_64-linux aarch64-linux)
    ;;
  *)
    fail "unsupported target kind '$target_kind'; choose darwin or nixos"
    ;;
esac

if ! prompt choose "${supported_platforms[@]}"; then
  handle_prompt_failure
fi
platform=$prompt_result
platform_supported=0
for supported_platform in "${supported_platforms[@]}"; do
  if [[ $platform == "$supported_platform" ]]; then
    platform_supported=1
    break
  fi
done
((platform_supported == 1)) || fail "unsupported system '$platform' for target kind '$target_kind'"

if ! prompt input --header 'Machine output name' --placeholder 'for example, my-machine'; then
  handle_prompt_failure
fi
machine_name=$prompt_result
is_nonempty_text 'Machine name' "$machine_name"
if [[ ! $machine_name =~ ^[[:alnum:]][[:alnum:]_-]*$ || ${#machine_name} -gt 63 ]]; then
  fail "invalid machine name '$machine_name'; use 1-63 letters, digits, underscores, or hyphens, starting with a letter or digit"
fi
machine_destination="$repo_root/machines/$machine_name"
catalog_destination="$generated_dir/$machine_name.nix"
if [[ -e $machine_destination || -L $machine_destination || -e $catalog_destination || -L $catalog_destination ]]; then
  fail "machine '$machine_name' already exists in a machine directory or generated catalog entry"
fi
if ! catalog_names=$(read_catalog_names); then
  fail "could not read existing machine names from $catalog_file"
fi
while IFS= read -r existing_name; do
  if [[ $existing_name == "$machine_name" ]]; then
    fail "machine '$machine_name' already exists in the machine catalog"
  fi
done <<< "$catalog_names"

if ! prompt input --header 'Hostname' --value "$machine_name"; then
  handle_prompt_failure
fi
hostname=$prompt_result
is_nonempty_text 'Hostname' "$hostname"
if [[ ! $hostname =~ ^[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?$ ]]; then
  fail "invalid hostname '$hostname'; use a DNS hostname of 1-63 letters, digits, or hyphens"
fi
if ! host_collisions=$(read_catalog_host_collisions "$hostname"); then
  fail "could not check whether hostname '$hostname' is already in use"
fi
if [[ -n $host_collisions ]]; then
  fail "hostname '$hostname' is already assigned to machine(s): ${host_collisions//$'\n'/, }"
fi

if ! prompt input --header "Primary user's full name" --placeholder 'Full name'; then
  handle_prompt_failure
fi
full_name=$prompt_result
is_nonempty_text 'Full name' "$full_name"

if ! prompt input --header 'Primary user account name' --placeholder 'account-name'; then
  handle_prompt_failure
fi
account_name=$prompt_result
is_nonempty_text 'Account name' "$account_name"
if [[ ! $account_name =~ ^[a-z_][a-z0-9_-]*$ || ${#account_name} -gt 32 ]]; then
  fail "invalid account name '$account_name'; use up to 32 lowercase letters, digits, underscores, or hyphens, starting with a letter or underscore"
fi

if ! prompt input --header 'Primary user email address' --placeholder 'name@example.test'; then
  handle_prompt_failure
fi
email=$prompt_result
is_nonempty_text 'Email address' "$email"
if [[ ! $email =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  fail "invalid email address '$email'"
fi

if [[ $target_kind == darwin ]]; then
  state_version=4
else
  if ! prompt input --header 'NixOS state version (for example, 24.11)' --placeholder '24.11'; then
    handle_prompt_failure
  fi
  state_version=$prompt_result
  is_nonempty_text 'NixOS state version' "$state_version"
fi

if ! prompt choose "${profiles[@]}"; then
  handle_prompt_failure
fi
secret_profile=$prompt_result
profile_supported=0
for configured_profile in "${profiles[@]}"; do
  if [[ $secret_profile == "$configured_profile" ]]; then
    profile_supported=1
    break
  fi
done
((profile_supported == 1)) || fail "unsupported SecretSpec profile '$secret_profile'"

if ! archetype_records=$(read_manifest_archetypes "$platform"); then
  fail "could not read compatible archetypes for system '$platform' from $options_file"
fi
archetype_labels=()
archetype_modules=()
while IFS=$'\t' read -r label archetype_kind module_path; do
  [[ -n $label ]] || continue
  [[ $archetype_kind == "$target_kind" ]] || continue
  if [[ ! $module_path =~ ^library/archetypes/[[:alnum:]_.-]+\.nix$ || ! -f $repo_root/$module_path ]]; then
    fail "wizard manifest references a missing or unsafe archetype module '$module_path'"
  fi
  archetype_labels+=("$label")
  archetype_modules+=("$module_path")
done <<< "$archetype_records"
(( ${#archetype_labels[@]} > 0 )) || fail "no archetypes are configured for system '$platform' and target kind '$target_kind'"

if ! prompt choose "${archetype_labels[@]}"; then
  handle_prompt_failure
fi
selected_archetype=$prompt_result
selected_module=
for index in "${!archetype_labels[@]}"; do
  if [[ ${archetype_labels[$index]} == "$selected_archetype" ]]; then
    selected_module=${archetype_modules[$index]}
    break
  fi
done
[[ -n $selected_module ]] || fail "unsupported archetype '$selected_archetype' for system '$platform'"

if ! role_records=$(read_manifest_roles "$platform"); then
  fail "could not read available roles for system '$platform' from $options_file"
fi
available_roles=()
while IFS= read -r role; do
  [[ -n $role ]] && available_roles+=("$role")
done <<< "$role_records"
if (( ${#available_roles[@]} == 0 )); then
  fail "no additional roles are configured for system '$platform'"
fi
if ! prompt choose --no-limit "${available_roles[@]}"; then
  handle_prompt_failure
fi
selected_role_output=$prompt_result
selected_roles=()
while IFS= read -r selected_role; do
  [[ -n $selected_role ]] || continue
  role_supported=0
  for available_role in "${available_roles[@]}"; do
    if [[ $selected_role == "$available_role" ]]; then
      role_supported=1
      break
    fi
  done
  ((role_supported == 1)) || fail "unsupported additional role '$selected_role' for system '$platform'"
  for existing_role in "${selected_roles[@]}"; do
    [[ $existing_role != "$selected_role" ]] || fail "additional role '$selected_role' was selected more than once"
  done
  selected_roles+=("$selected_role")
done <<< "$selected_role_output"

printf '\nMachine target summary\n'
printf '  Target kind:        %s\n' "$target_kind"
printf '  System:             %s\n' "$platform"
printf '  Machine name:       %s\n' "$machine_name"
printf '  Hostname:            %s\n' "$hostname"
printf '  Primary user:        %s (%s)\n' "$full_name" "$account_name"
printf '  Email:               %s\n' "$email"
printf '  State version:       %s\n' "$state_version"
printf '  SecretSpec profile:  %s\n' "$secret_profile"
printf '  Archetype:           %s (%s)\n' "$selected_archetype" "$selected_module"
if (( ${#selected_roles[@]} == 0 )); then
  printf '  Additional roles:    none\n'
else
  printf '  Additional roles:    %s\n' "$(IFS=', '; printf '%s' "${selected_roles[*]}")"
fi
if [[ $target_kind == nixos ]]; then
  printf '  Follow-up: configure NixOS hardware/facter and disk layout manually.\n'
fi
printf '  This creates configuration only; it will not build, install, deploy, switch, or configure disks.\n\n'

if "$gum_bin" confirm "Create machine '$machine_name' with these settings?"; then
  :
else
  confirm_status=$?
  case $confirm_status in
    1|130) exit 0 ;;
    *) fail "Gum confirmation failed with exit status $confirm_status" ;;
  esac
fi

# Recheck both destinations after confirmation so existing output is never
# overwritten, even if another process created a target during the prompts.
if [[ -e $machine_destination || -L $machine_destination || -e $catalog_destination || -L $catalog_destination ]]; then
  fail "machine '$machine_name' already exists in a machine directory or generated catalog entry"
fi
if ! catalog_names=$(read_catalog_names); then
  fail "could not recheck existing machine names in $catalog_file"
fi
while IFS= read -r existing_name; do
  [[ $existing_name != "$machine_name" ]] || fail "machine '$machine_name' already exists in the machine catalog"
done <<< "$catalog_names"
if ! host_collisions=$(read_catalog_host_collisions "$hostname"); then
  fail "could not recheck whether hostname '$hostname' is already in use"
fi
[[ -z $host_collisions ]] || fail "hostname '$hostname' is already assigned to machine(s): ${host_collisions//$'\n'/, }"

if [[ ! -d $generated_dir ]]; then
  mkdir -- "$generated_dir" || fail "could not create generated machine catalog directory: $generated_dir"
  generated_dir_created=1
fi
temporary_dir=$(mktemp -d "$repo_root/.machine-scaffold.XXXXXX") || fail "could not create a temporary output directory under $repo_root"
staged_machine="$temporary_dir/$machine_name"
staged_catalog="$temporary_dir/$machine_name.nix"
mkdir -- "$staged_machine"

archetype_import="../../$selected_module"
state_version_nix=$(nix_string "$state_version")
account_name_nix=$(nix_string "$account_name")
full_name_nix=$(nix_string "$full_name")
email_nix=$(nix_string "$email")
{
  printf '{ lib, ... }:\n{\n'
  printf '  # Target system: %s\n' "$platform"
  printf '  imports = [\n    %s\n  ];\n\n' "$archetype_import"
  if [[ $target_kind == darwin ]]; then
    printf '  system.stateVersion = 4;\n'
    printf '  system.primaryUser = %s;\n' "$account_name_nix"
  else
    printf '  system.stateVersion = %s;\n' "$state_version_nix"
  fi
  printf '  myConfig.users = lib.mkDefault [\n'
  printf '    { name = %s; fullName = %s; email = %s; }\n' "$account_name_nix" "$full_name_nix" "$email_nix"
  printf '  ];\n'
  for selected_role in "${selected_roles[@]}"; do
    role_nix=$(nix_string "$selected_role")
    printf '  myConfig.roles.%s.enable = true;\n' "$role_nix"
  done
  printf '}\n'
} > "$staged_machine/default.nix"

machine_name_nix=$(nix_string "$machine_name")
hostname_nix=$(nix_string "$hostname")
platform_nix=$(nix_string "$platform")
secret_profile_nix=$(nix_string "$secret_profile")
if [[ $target_kind == darwin ]]; then
  constructor=darwinMachine
else
  constructor=nixosMachine
fi
{
  printf '{ %s, %s }:\n{\n' darwinMachine nixosMachine
  printf '  %s = %s {\n' "$machine_name_nix" "$constructor"
  printf '    secretProfile = %s;\n' "$secret_profile_nix"
  printf '    system = %s;\n' "$platform_nix"
  printf '    hostname = %s;\n' "$hostname_nix"
  printf '    modules = [ ../../../machines/%s ];\n' "$machine_name"
  printf '    overrides = {\n'
  printf '      users = [\n'
  printf '        {\n'
  printf '          name = %s;\n' "$account_name_nix"
  printf '          fullName = %s;\n' "$full_name_nix"
  printf '          email = %s;\n' "$email_nix"
  printf '        }\n'
  printf '      ];\n'
  printf '    };\n'
  printf '  };\n'
  printf '}\n'
} > "$staged_catalog"

# The two final names are absent, and the staged outputs are complete before
# either one is published. `mv -n` is supported by both GNU and BSD mv.
if [[ -e $machine_destination || -L $machine_destination || -e $catalog_destination || -L $catalog_destination ]]; then
  fail "machine '$machine_name' already exists in a machine directory or generated catalog entry"
fi
if ! mv -n -- "$staged_machine" "$machine_destination" || [[ -e $staged_machine ]]; then
  fail "could not publish machine directory '$machine_destination'; existing output was left untouched"
fi
machine_created=1
if [[ ! -f $machine_destination/default.nix ]]; then
  fail "machine directory move did not publish the expected default.nix; generated output was rolled back"
fi
if [[ -e $catalog_destination || -L $catalog_destination ]]; then
  fail "generated catalog entry '$catalog_destination' appeared during generation; machine output was rolled back"
fi
if ! mv -n -- "$staged_catalog" "$catalog_destination" || [[ -e $staged_catalog ]]; then
  fail "could not publish generated catalog entry '$catalog_destination'; machine output was rolled back"
fi
catalog_created=1
generation_succeeded=1
printf 'Created machine module: %s\n' "$machine_destination/default.nix"
printf 'Created catalog entry: %s\n' "$catalog_destination"

if [[ $target_kind == darwin ]]; then
  configuration_set=darwinConfigurations
else
  configuration_set=nixosConfigurations
fi
target_expression=".#${configuration_set}.${machine_name}.config.system.build.toplevel.drvPath"
if "$gum_bin" confirm "Evaluate the new $configuration_set target '$machine_name' now?"; then
  if nix eval --raw "$target_expression"; then
    printf 'Successfully evaluated %s.\n' "$target_expression"
  else
    evaluation_status=$?
    printf '\nEvaluation failed for %s; generated files were kept:\n' "$target_expression" >&2
    printf '  %s/default.nix\n  %s\n' "$machine_destination" "$catalog_destination" >&2
    printf 'If Nix reports that the configuration is missing, the flake may be ignoring newly generated untracked files. Review the generated files and make them visible to Nix through your normal version-control workflow before retrying; this wizard will not stage them.\n' >&2
    exit "$evaluation_status"
  fi
else
  evaluation_prompt_status=$?
  case $evaluation_prompt_status in
    1|130)
      printf '\nNext steps:\n'
      printf '  Review %s/default.nix and %s\n' "$machine_destination" "$catalog_destination"
      printf '  Evaluate this target with: nix eval --raw %s\n' "$target_expression"
      if [[ $target_kind == nixos ]]; then
        printf '  Configure NixOS hardware/facter inputs and disk layout manually before building or installing.\n'
      fi
      printf '  This wizard does not build, install, deploy, or switch the configuration.\n'
      ;;
    *)
      fail "Gum evaluation confirmation failed with exit status $evaluation_prompt_status"
      ;;
  esac
fi
