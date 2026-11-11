#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
scaffold_script=${MACHINE_SCAFFOLD_SCRIPT:-"$repo_root/scripts/machine-scaffold.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/fixture"
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"
export GUM_BIN="$tmp/bin/gum"
export GUM_RESPONSE_FILE="$tmp/gum-responses"
export GUM_CALL_LOG="$tmp/gum-calls"
export GUM_EXHAUSTION_LOG="$tmp/gum-exhaustions"
export MACHINE_SCAFFOLD_TEST_COMMAND_LOG="$tmp/unsafe-commands"
export MACHINE_SCAFFOLD_TEST_NIX_LOG="$tmp/nix-commands"
export MACHINE_SCAFFOLD_TEST_NIX_STATE_DIR="$tmp/nix-state"
export MACHINE_SCAFFOLD_TEST_EVAL_TARGET=
export MACHINE_SCAFFOLD_TEST_EVAL_STATUS=0
export MACHINE_SCAFFOLD_TEST_EVAL_DIAGNOSTIC=
export MACHINE_SCAFFOLD_TEST_EVAL_OUTPUT=/nix/store/fake-target.drv
export MACHINE_SCAFFOLD_TEST_REAL_NIX=${MACHINE_SCAFFOLD_TEST_REAL_NIX:-$(command -v nix || true)}
mkdir -p "$MACHINE_SCAFFOLD_TEST_NIX_STATE_DIR"
: > "$GUM_CALL_LOG"
: > "$GUM_EXHAUSTION_LOG"
: > "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG"
: > "$MACHINE_SCAFFOLD_TEST_NIX_LOG"

# Gum consumes one queued answer per call. A pipe-delimited answer models a
# multi-select response; __CANCEL__ models Escape/Ctrl-C without a TTY.
printf '#!%s\n' "$BASH" > "$GUM_BIN"
cat >> "$GUM_BIN" <<'GUM'
set -euo pipefail
command_name=${1:-}
shift || true
printf '%s %s\n' "$command_name" "$*" >> "$GUM_CALL_LOG"
if ! IFS= read -r response < "$GUM_RESPONSE_FILE"; then
  printf '%s\n' "$command_name" >> "$GUM_EXHAUSTION_LOG"
  echo "fake gum: no queued response for $command_name" >&2
  exit 97
fi
tail -n +2 "$GUM_RESPONSE_FILE" > "$GUM_RESPONSE_FILE.next"
mv "$GUM_RESPONSE_FILE.next" "$GUM_RESPONSE_FILE"
if [[ "$response" == __CANCEL__ ]]; then
  exit 130
fi
if [[ "$command_name" == confirm && "$*" == "Evaluate the new "* \
  && ( -n ${MACHINE_SCAFFOLD_TEST_EVAL_MODULE:-} || -n ${MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY:-} ) ]]; then
  for generated_path in \
    "${MACHINE_SCAFFOLD_TEST_EVAL_MODULE:-}" \
    "${MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY:-}"; do
    if [[ -z $generated_path || ! -f $generated_path ]]; then
      printf 'evaluation was offered before generated output existed: %s\n' "$generated_path" >&2
      exit 96
    fi
  done
fi
if [[ "$command_name" == confirm ]]; then
  [[ "$response" == yes || "$response" == y ]]
  exit
fi
if [[ "$response" == *'|'* ]]; then
  printf '%s\n' "$response" | tr '|' '\n'
else
  printf '%s\n' "$response"
fi
GUM
chmod +x "$GUM_BIN"

# Guard machine-operation and disk utilities so accidental execution is
# observable and can never reach the host running the test.
printf '#!%s\n' "$BASH" > "$tmp/bin/devenv"
cat >> "$tmp/bin/devenv" <<'GUARD'
printf 'devenv %s\n' "$*" >> "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG"
exit 98
GUARD
chmod +x "$tmp/bin/devenv"
# Permit only read-only nix eval (forwarded to the real Nix executable). Every
# other nix subcommand, including build/run/profile/install/deploy operations,
# is logged and rejected; legacy Nix entry points are guarded too.
printf '#!%s\n' "$BASH" > "$tmp/bin/nix"
cat >> "$tmp/bin/nix" <<'GUARD'
set -euo pipefail
log_command() {
  printf 'nix' >> "$MACHINE_SCAFFOLD_TEST_NIX_LOG"
  printf ' %q' "$@" >> "$MACHINE_SCAFFOLD_TEST_NIX_LOG"
  printf '\n' >> "$MACHINE_SCAFFOLD_TEST_NIX_LOG"
}
log_command "$@"
if [[ ${1:-} == eval ]]; then
  target_eval=
  for argument in "$@"; do
    if [[ "$argument" == --write-to || "$argument" == --write-to=* ]]; then
      printf 'nix %s\n' "$*" >> "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG"
      exit 98
    fi
    if [[ $argument =~ ^\.\#(nixos|darwin)Configurations\.[^.]+\.config\.system\.build\.toplevel\.drvPath$ ]]; then
      target_eval=$argument
    fi
  done
  if [[ -n $target_eval ]]; then
    if [[ $target_eval != ${MACHINE_SCAFFOLD_TEST_EVAL_TARGET:-} ]]; then
      printf 'unexpected target evaluation: %s (expected %s)\n' \
        "$target_eval" "${MACHINE_SCAFFOLD_TEST_EVAL_TARGET:-none}" >&2
      exit 97
    fi
    if [[ ${MACHINE_SCAFFOLD_TEST_EVAL_STATUS:-0} != 0 ]]; then
      printf '%s\n' "${MACHINE_SCAFFOLD_TEST_EVAL_DIAGNOSTIC:-fake target evaluation failed}" >&2
      exit "${MACHINE_SCAFFOLD_TEST_EVAL_STATUS}"
    fi
    printf '%s\n' "${MACHINE_SCAFFOLD_TEST_EVAL_OUTPUT:-/nix/store/fake-target.drv}"
    exit 0
  fi
  if [[ -n ${MACHINE_SCAFFOLD_TEST_REAL_NIX:-} ]]; then
    NIX_STATE_DIR=$MACHINE_SCAFFOLD_TEST_NIX_STATE_DIR \
      exec "$MACHINE_SCAFFOLD_TEST_REAL_NIX" --extra-experimental-features nix-command "$@"
  fi
fi
printf 'nix %s\n' "$*" >> "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG"
exit 98
GUARD
chmod +x "$tmp/bin/nix"
for command_name in \
  darwin-rebuild nixos-rebuild nixos-install nixos-anywhere \
  deploy deploy-rs colmena nixops nixops4 \
  nix-build nix-shell nix-env nix-store nix-channel \
  disko diskutil parted fdisk sfdisk mkfs mkfs.ext4 mount umount sudo systemctl; do
  printf '#!%s\n' "$BASH" > "$tmp/bin/$command_name"
  cat >> "$tmp/bin/$command_name" <<'GUARD'
printf '%s %s\n' "${0##*/}" "$*" >> "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG"
exit 98
GUARD
  chmod +x "$tmp/bin/$command_name"
done

new_fixture() {
  rm -rf "$fixture"
  mkdir -p \
    "$fixture/machines" \
    "$fixture/library/machines/generated" \
    "$fixture/library/archetypes" \
    "$fixture/templates/machine"

  cat > "$fixture/library/machines/catalog.nix" <<'NIX'
{ ... }: {
  catalog-collision = {};
}
NIX
  cat > "$fixture/library/machines/wizard-options.nix" <<'NIX'
{
  aarch64-darwin = {
    archetypes = [
      { label = "Fixture Darwin"; kind = "darwin"; module = "library/archetypes/fixture-darwin.nix"; }
    ];
    roles = [ "developer" "desktop" ];
  };
  aarch64-linux = {
    archetypes = [
      { label = "Fixture Linux"; kind = "nixos"; module = "library/archetypes/fixture-linux.nix"; }
    ];
    roles = [ "developer" "desktop" ];
  };
  x86_64-linux = {
    archetypes = [
      { label = "Fixture Linux"; kind = "nixos"; module = "library/archetypes/fixture-linux.nix"; }
    ];
    roles = [ "developer" "desktop" ];
  };
}
NIX
  printf '{ ... }: {}\n' > "$fixture/library/archetypes/fixture-darwin.nix"
  printf '{ ... }: {}\n' > "$fixture/library/archetypes/fixture-linux.nix"
  # The fixture keeps template inputs present and simple without depending on
  # production template wording or the real repository catalog.
  printf '# fixture machine template\n' > "$fixture/templates/machine/default.nix"
  printf '# fixture generated-catalog template\n' > "$fixture/templates/machine/catalog-entry.nix"
  cat > "$fixture/secretspec.toml" <<'TOML'
[profiles.Personal]
[profiles.Opnix]
[profiles.Opnix.defaults]
[profiles.MegamanX.defaults]
TOML
}

queue_answers() {
  printf '%s\n' "$@" > "$GUM_RESPONSE_FILE"
  : > "$GUM_CALL_LOG"
  : > "$GUM_EXHAUSTION_LOG"
}

run_scaffold() {
  local case_name=$1
  local status
  shift
  queue_answers "$@"
  mkdir -p "$tmp/output"
  if MACHINE_SCAFFOLD_ROOT="$fixture" \
    MACHINE_SCAFFOLD_SCRIPT="$scaffold_script" \
    GUM_BIN="$GUM_BIN" \
    bash "$scaffold_script" > "$tmp/output/$case_name.log" 2>&1; then
    status=0
  else
    status=$?
  fi
  if [[ -s "$GUM_EXHAUSTION_LOG" ]]; then
    echo "fake Gum exhausted its queued responses in case '$case_name':" >&2
    cat "$GUM_EXHAUSTION_LOG" >&2
    cat "$tmp/output/$case_name.log" >&2
    exit 1
  fi
  return "$status"
}

expect_success() {
  local case_name=$1
  shift
  if run_scaffold "$case_name" "$@"; then
    return 0
  fi
  echo "expected machine scaffold case '$case_name' to succeed:" >&2
  cat "$tmp/output/$case_name.log" >&2
  return 1
}

expect_rejected_with_diagnostic() {
  local case_name=$1
  local diagnostic_pattern=$2
  shift 2
  if run_scaffold "$case_name" "$@"; then
    echo "expected machine scaffold case '$case_name' to be rejected" >&2
    cat "$tmp/output/$case_name.log" >&2
    return 1
  fi
  if ! grep -Eiq -- "$diagnostic_pattern" "$tmp/output/$case_name.log"; then
    echo "case '$case_name' failed without its expected validation diagnostic ($diagnostic_pattern):" >&2
    cat "$tmp/output/$case_name.log" >&2
    return 1
  fi
}

expect_rejected_without_writes() {
  local case_name=$1
  local machine_name=$2
  local diagnostic_pattern=$3
  shift 3
  expect_rejected_with_diagnostic "$case_name" "$diagnostic_pattern" "$@" || return 1
  [[ ! -e "$fixture/machines/$machine_name" ]] || {
    echo "rejected case '$case_name' left a machine directory" >&2
    return 1
  }
  [[ ! -e "$fixture/library/machines/generated/$machine_name.nix" ]] || {
    echo "rejected case '$case_name' left a generated catalog file" >&2
    return 1
  }
}

snapshot_fixture_tree() {
  local snapshot=$1
  (
    cd "$fixture"
    while IFS= read -r -d '' path; do
      local metadata digest
      metadata=$(stat --printf='%F %a %u %g %s %y %z' -- "$path")
      printf '%q %s' "$path" "$metadata"
      if [[ -f "$path" && ! -L "$path" ]]; then
        digest=$(sha256sum < "$path")
        printf ' %s' "${digest%% *}"
      elif [[ -L "$path" ]]; then
        printf ' %q' "$(readlink -- "$path")"
      fi
      printf '\n'
    done < <(find . -mindepth 1 -print0 | LC_ALL=C sort -z)
  ) > "$snapshot"
}

assert_fixture_unchanged() {
  local case_name=$1
  local before=$2
  local after="$tmp/$case_name.fixture-after"
  snapshot_fixture_tree "$after"
  cmp -s "$before" "$after" || {
    echo "case '$case_name' changed the fixture tree:" >&2
    echo 'fixture tree before:' >&2
    cat "$before" >&2
    echo 'fixture tree after:' >&2
    cat "$after" >&2
    return 1
  }
}

assert_file_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || {
    printf 'expected %s to contain %s\n' "$file" "$expected" >&2
    cat "$file" >&2
    return 1
  }
}

assert_summary_contains() {
  local case_name=$1
  local expected=$2
  assert_file_contains "$tmp/output/$case_name.log" "$expected"
}

assert_profile_choices_exclude_nested_defaults() {
  local case_name=$1
  if ! grep -Fqx 'choose Personal Opnix' "$GUM_CALL_LOG"; then
    echo "case '$case_name' did not present only the top-level SecretSpec profiles:" >&2
    cat "$GUM_CALL_LOG" >&2
    return 1
  fi
  if grep -Eq 'Opnix\.defaults|MegamanX\.defaults' "$GUM_CALL_LOG"; then
    echo "case '$case_name' presented a nested SecretSpec defaults section as a profile choice:" >&2
    cat "$GUM_CALL_LOG" >&2
    return 1
  fi
}

assert_no_disk_configuration() {
  local machine_name=$1
  local generated="$fixture/machines/$machine_name/default.nix"
  if grep -Eiq 'disko|disk-configs|disk[[:space:]]*=' "$generated"; then
    echo "NixOS scaffold unexpectedly contains disk configuration for $machine_name" >&2
    cat "$generated" >&2
    return 1
  fi
}

assert_target_eval_called() {
  local case_name=$1 target=$2 expected="nix eval --raw $2"
  grep -Fqx -- "$expected" "$MACHINE_SCAFFOLD_TEST_NIX_LOG" || {
    printf "case '%s' did not evaluate the exact target configuration %s:\n" "$case_name" "$target" >&2
    cat "$MACHINE_SCAFFOLD_TEST_NIX_LOG" >&2
    return 1
  }
}

assert_target_eval_not_called() {
  local case_name=$1 target=$2 expected="nix eval --raw $2"
  if grep -Fqx -- "$expected" "$MACHINE_SCAFFOLD_TEST_NIX_LOG"; then
    printf "case '%s' unexpectedly evaluated the target configuration %s:\n" "$case_name" "$target" >&2
    cat "$MACHINE_SCAFFOLD_TEST_NIX_LOG" >&2
    return 1
  fi
}

assert_eval_prompt_offered() {
  local case_name=$1 configuration_set=$2 machine_name=$3
  if ! grep -Fqx -- "confirm Evaluate the new $configuration_set target '$machine_name' now?" "$GUM_CALL_LOG"; then
    printf "case '%s' did not offer the expected optional target evaluation prompt:\n" "$case_name" >&2
    cat "$GUM_CALL_LOG" >&2
    return 1
  fi
}

assert_no_forbidden_commands() {
  if [[ -s "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG" ]]; then
    echo 'wizard invoked a Nix build/run/install, deployment, activation, or disk command:' >&2
    cat "$MACHINE_SCAFFOLD_TEST_COMMAND_LOG" >&2
    return 1
  fi
  while IFS= read -r nix_command; do
    [[ "$nix_command" =~ ^nix[[:space:]]+eval([[:space:]]|$) ]] || {
      echo 'wizard invoked a non-read-only nix command:' >&2
      printf '%s\n' "$nix_command" >&2
      return 1
    }
  done < "$MACHINE_SCAFFOLD_TEST_NIX_LOG"
}

# Darwin contract: selected platform/archetype, distinct multiple roles,
# identity, hostname, default state version, secret profile, and summary.
new_fixture
MACHINE_SCAFFOLD_TEST_EVAL_MODULE="$fixture/machines/darwin-wizard/default.nix" \
  MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY="$fixture/library/machines/generated/darwin-wizard.nix" \
  expect_success darwin-rich \
  darwin aarch64-darwin darwin-wizard wizard-host \
  'Ada Lovelace' ada ada@example.test Personal \
  'Fixture Darwin' 'developer|desktop' yes no no
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'aarch64-darwin'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'fixture-darwin.nix'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'developer'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'desktop'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'Ada Lovelace'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'ada@example.test'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" 'stateVersion'
assert_file_contains "$fixture/machines/darwin-wizard/default.nix" '4'
assert_file_contains "$fixture/library/machines/generated/darwin-wizard.nix" 'Personal'
assert_file_contains "$fixture/library/machines/generated/darwin-wizard.nix" 'wizard-host'
assert_file_contains "$fixture/library/machines/generated/darwin-wizard.nix" '{ darwinMachine, ... }:'
assert_file_contains "$fixture/library/machines/generated/darwin-wizard.nix" '= darwinMachine {'
if grep -Fq 'nixosMachine' "$fixture/library/machines/generated/darwin-wizard.nix"; then
  echo 'Darwin catalog entry unexpectedly binds the unused NixOS constructor' >&2
  exit 1
fi
assert_profile_choices_exclude_nested_defaults darwin-rich
for summary_value in aarch64-darwin 'Fixture Darwin' developer desktop 'Ada Lovelace' ada@example.test Personal; do
  assert_summary_contains darwin-rich "$summary_value"
done
assert_eval_prompt_offered darwin-rich darwinConfigurations darwin-wizard
assert_target_eval_not_called darwin-rich \
  '.#darwinConfigurations.darwin-wizard.config.system.build.toplevel.drvPath'
assert_file_contains "$tmp/output/darwin-rich.log" \
  'Evaluate this target with: nix eval --raw .#darwinConfigurations.darwin-wizard.config.system.build.toplevel.drvPath'
assert_no_forbidden_commands

# Both NixOS platforms require an explicit state version and leave disk setup
# to a human follow-up; there is deliberately no disk selection in this flow.
new_fixture
expect_success nixos-arm \
  nixos aarch64-linux nixos-arm arm-host \
  'Grace Hopper' grace grace@example.test 24.11 Opnix \
  'Fixture Linux' developer yes no no
assert_file_contains "$fixture/machines/nixos-arm/default.nix" 'aarch64-linux'
assert_file_contains "$fixture/machines/nixos-arm/default.nix" '24.11'
assert_file_contains "$fixture/library/machines/generated/nixos-arm.nix" 'Opnix'
assert_file_contains "$fixture/library/machines/generated/nixos-arm.nix" '{ nixosMachine, ... }:'
assert_file_contains "$fixture/library/machines/generated/nixos-arm.nix" '= nixosMachine {'
if grep -Fq 'darwinMachine' "$fixture/library/machines/generated/nixos-arm.nix"; then
  echo 'NixOS catalog entry unexpectedly binds the unused Darwin constructor' >&2
  exit 1
fi
assert_no_disk_configuration nixos-arm
assert_no_forbidden_commands

new_fixture
expect_success nixos-x86 \
  nixos x86_64-linux nixos-x86 x86-host \
  'Grace Hopper' grace grace@example.test 25.05 Personal \
  'Fixture Linux' desktop yes no no
assert_file_contains "$fixture/machines/nixos-x86/default.nix" 'x86_64-linux'
assert_file_contains "$fixture/machines/nixos-x86/default.nix" '25.05'
assert_no_disk_configuration nixos-x86
assert_no_forbidden_commands

# Optional evaluation is offered only after generation, and targets the exact
# selected flake configuration for both supported operating-system families.
new_fixture
MACHINE_SCAFFOLD_TEST_EVAL_TARGET='.#darwinConfigurations.eval-darwin.config.system.build.toplevel.drvPath' \
  MACHINE_SCAFFOLD_TEST_EVAL_MODULE="$fixture/machines/eval-darwin/default.nix" \
  MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY="$fixture/library/machines/generated/eval-darwin.nix" \
  expect_success eval-darwin \
  darwin aarch64-darwin eval-darwin eval-darwin-host \
  'Test User' tester test@example.test Personal 'Fixture Darwin' developer yes yes
assert_eval_prompt_offered eval-darwin darwinConfigurations eval-darwin
assert_target_eval_called eval-darwin \
  '.#darwinConfigurations.eval-darwin.config.system.build.toplevel.drvPath'
assert_file_contains "$tmp/output/eval-darwin.log" '/nix/store/fake-target.drv'
[[ -f "$fixture/machines/eval-darwin/default.nix" ]]
[[ -f "$fixture/library/machines/generated/eval-darwin.nix" ]]
assert_no_forbidden_commands

new_fixture
MACHINE_SCAFFOLD_TEST_EVAL_TARGET='.#nixosConfigurations.eval-nixos.config.system.build.toplevel.drvPath' \
  MACHINE_SCAFFOLD_TEST_EVAL_MODULE="$fixture/machines/eval-nixos/default.nix" \
  MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY="$fixture/library/machines/generated/eval-nixos.nix" \
  expect_success eval-nixos \
  nixos x86_64-linux eval-nixos eval-nixos-host \
  'Test User' tester test@example.test 25.05 Personal \
  'Fixture Linux' developer yes yes
assert_eval_prompt_offered eval-nixos nixosConfigurations eval-nixos
assert_target_eval_called eval-nixos \
  '.#nixosConfigurations.eval-nixos.config.system.build.toplevel.drvPath'
assert_file_contains "$tmp/output/eval-nixos.log" '/nix/store/fake-target.drv'
[[ -f "$fixture/machines/eval-nixos/default.nix" ]]
[[ -f "$fixture/library/machines/generated/eval-nixos.nix" ]]
assert_no_forbidden_commands

# An evaluator diagnostic and nonzero status are preserved, while generation
# remains intact for the operator to review and correct.
new_fixture
failure_diagnostic='fixture target evaluation diagnostic: missing hardware configuration'
if MACHINE_SCAFFOLD_TEST_EVAL_TARGET='.#nixosConfigurations.eval-fails.config.system.build.toplevel.drvPath' \
  MACHINE_SCAFFOLD_TEST_EVAL_STATUS=23 \
  MACHINE_SCAFFOLD_TEST_EVAL_DIAGNOSTIC="$failure_diagnostic" \
  MACHINE_SCAFFOLD_TEST_EVAL_MODULE="$fixture/machines/eval-fails/default.nix" \
  MACHINE_SCAFFOLD_TEST_EVAL_CATALOG_ENTRY="$fixture/library/machines/generated/eval-fails.nix" \
  run_scaffold eval-fails \
    nixos aarch64-linux eval-fails eval-fails-host \
    'Test User' tester test@example.test 25.05 Personal \
    'Fixture Linux' developer yes yes; then
  echo 'expected optional target evaluation failure to return a nonzero status' >&2
  exit 1
fi
assert_eval_prompt_offered eval-fails nixosConfigurations eval-fails
assert_target_eval_called eval-fails \
  '.#nixosConfigurations.eval-fails.config.system.build.toplevel.drvPath'
assert_file_contains "$tmp/output/eval-fails.log" "$failure_diagnostic"
assert_file_contains "$tmp/output/eval-fails.log" 'generated files were kept'
[[ -f "$fixture/machines/eval-fails/default.nix" ]]
[[ -f "$fixture/library/machines/generated/eval-fails.nix" ]]
assert_no_forbidden_commands

# Canceling a prompt and declining the final confirmation must leave no
# generated output. Gum may report cancellation with a non-zero status.
new_fixture
snapshot_fixture_tree "$tmp/cancel-at-platform.fixture-before"
expect_success cancel-at-platform darwin __CANCEL__
[[ -s "$GUM_CALL_LOG" ]] || {
  echo 'prompt cancellation case did not reach a Gum prompt' >&2
  cat "$tmp/output/cancel-at-platform.log" >&2
  exit 1
}
assert_fixture_unchanged cancel-at-platform "$tmp/cancel-at-platform.fixture-before"
assert_no_forbidden_commands

new_fixture
snapshot_fixture_tree "$tmp/declined.fixture-before"
expect_success declined darwin aarch64-darwin declined declined-host \
  'Test User' tester test@example.test Personal 'Fixture Darwin' developer no
grep -Eq '^confirm([[:space:]]|$)' "$GUM_CALL_LOG" || {
  echo 'declined case did not reach the final confirmation prompt' >&2
  cat "$tmp/output/declined.log" >&2
  exit 1
}
assert_fixture_unchanged declined "$tmp/declined.fixture-before"
assert_no_forbidden_commands

# Required values and machine names are rejected before either destination is
# written. Unsupported archetype/role answers are rejected the same way.
new_fixture
expect_rejected_without_writes missing-email missing-email \
  '(email|e-mail).*(required|empty|missing)|(required|empty|missing).*(email|e-mail)' \
  darwin aarch64-darwin missing-email missing-host 'Test User' tester '' \
  Personal 'Fixture Darwin' developer yes no
new_fixture
expect_rejected_without_writes invalid-name 'bad/name' \
  '(invalid|unsupported|not allowed|cannot).*(machine )?name|(machine )?name.*(invalid|unsupported|not allowed|cannot)' \
  darwin aarch64-darwin 'bad/name' bad-host 'Test User' tester test@example.test \
  Personal 'Fixture Darwin' developer yes no
new_fixture
expect_rejected_without_writes unsupported-archetype unsupported-archetype \
  '(unsupported|invalid|unknown).*(archetype|bundle)|(archetype|bundle).*(unsupported|invalid|unknown)' \
  darwin aarch64-darwin unsupported-archetype host 'Test User' tester test@example.test \
  Personal 'Fixture Linux' developer yes no
new_fixture
expect_rejected_without_writes unsupported-role unsupported-role \
  '(unsupported|invalid|unknown).*(role)|(role).*(unsupported|invalid|unknown)' \
  darwin aarch64-darwin unsupported-role host 'Test User' tester test@example.test \
  Personal 'Fixture Darwin' unavailable-role yes no

# A collision in the catalog, a pre-existing target directory, or an existing
# generated catalog file is never overwritten and produces no companion file.
new_fixture
expect_rejected_without_writes catalog-collision catalog-collision \
  '(already exists|collision|duplicate|reserved).*(machine|catalog|name)|(machine|catalog|name).*(already exists|collision|duplicate|reserved)' \
  darwin aarch64-darwin catalog-collision host 'Test User' tester test@example.test \
  Personal 'Fixture Darwin' developer yes no
new_fixture
mkdir -p "$fixture/machines/directory-collision"
printf 'keep this target intact\n' > "$fixture/machines/directory-collision/sentinel"
expect_rejected_with_diagnostic directory-collision \
  '(already exists|collision|duplicate|reserved).*(machine|catalog|name)|(machine|catalog|name).*(already exists|collision|duplicate|reserved)' \
  darwin aarch64-darwin directory-collision host 'Test User' tester test@example.test \
  Personal 'Fixture Darwin' developer yes no
[[ "$(cat "$fixture/machines/directory-collision/sentinel")" == 'keep this target intact' ]]
[[ ! -e "$fixture/library/machines/generated/directory-collision.nix" ]]
assert_no_forbidden_commands

new_fixture
printf 'keep this catalog file intact\n' > "$fixture/library/machines/generated/catalog-file-collision.nix"
expect_rejected_with_diagnostic catalog-file-collision \
  '(already exists|collision|duplicate|reserved).*(machine|catalog|name)|(machine|catalog|name).*(already exists|collision|duplicate|reserved)' \
  darwin aarch64-darwin catalog-file-collision host 'Test User' tester test@example.test \
  Personal 'Fixture Darwin' developer yes no
[[ "$(cat "$fixture/library/machines/generated/catalog-file-collision.nix")" == 'keep this catalog file intact' ]]
[[ ! -e "$fixture/machines/catalog-file-collision" ]]
assert_no_forbidden_commands

# Every invocation starts from an isolated fixture; no test case may invoke
# system management or disk commands, regardless of its outcome.
assert_no_forbidden_commands
echo 'Machine scaffold wizard contract tests passed'
