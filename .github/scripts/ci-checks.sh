#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 plan|build GROUP [TASK_INPUT_JSON]" >&2
  exit 64
}

[[ $# -ge 2 && $# -le 3 ]] || usage
mode="$1"
group="$2"
if [[ $# -ge 3 ]]; then
  task_input="$3"
elif [[ -n "${DEVENV_TASK_INPUT:-}" ]]; then
  task_input="$DEVENV_TASK_INPUT"
else
  task_input='{}'
fi
nix_bin="${NIX_BIN:-nix}"

case "$group" in
  pr|extended|non-vm|vm-pr|vm-extended|vm) ;;
  *) echo "Unknown CI check group '$group'" >&2; exit 64 ;;
esac

if ! jq -e 'type == "object"' <<< "$task_input" >/dev/null; then
  echo "Task input must be a JSON object" >&2
  exit 64
fi

current_system=$("$nix_bin" eval --impure --raw --expr 'builtins.currentSystem')
all_checks=$("$nix_bin" eval --json ".#checks.${current_system}" \
  --apply 'builtins.attrNames')

filter_for_group() {
  case "$1" in
    pr)
      jq -c '[.[] | select(. == "vm-role-generator" or (startswith("vm-") | not)) | select(startswith("overlay-") | not) | select(. != "module-coverage")]' <<< "$all_checks"
      ;;
    extended)
      jq -c '[.[] | select(startswith("overlay-"))]' <<< "$all_checks"
      ;;
    non-vm)
      jq -c '[.[] | select(. == "vm-role-generator" or (startswith("vm-") | not))]' <<< "$all_checks"
      ;;
    vm-pr)
      jq -cn --argjson available "$all_checks" \
        '["vm-users", "vm-ssh", "vm-packages"] | map(select(. as $check | $available | index($check) != null))'
      ;;
    vm-extended)
      jq -cn --argjson available "$all_checks" \
        '["vm-role-foundation", "vm-role-developer"] | map(select(. as $check | $available | index($check) != null))'
      ;;
    vm)
      jq -c '[.[] | select(startswith("vm-") and . != "vm-role-generator")]' <<< "$all_checks"
      ;;
  esac
}

selected_checks=$(filter_for_group "$group")
if [[ $(jq 'length' <<< "$selected_checks") -eq 0 ]]; then
  echo "No checks selected for group '$group' on $current_system" >&2
  exit 1
fi

case "$mode" in
  plan)
    batch_size=$(jq -er '.batchSize | numbers' <<< "$task_input") || {
      echo "Task input must contain a positive integer batchSize" >&2
      exit 64
    }
    if [[ ! "$batch_size" =~ ^[1-9][0-9]*$ ]]; then
      echo "batchSize must be a positive integer (got '$batch_size')" >&2
      exit 64
    fi

    if jq -e 'has("checkPrefixes")' <<< "$task_input" >/dev/null; then
      check_prefixes=$(jq -ce '.checkPrefixes | select(type == "array" and all(.[]; type == "string" and (. == "*" or test("^[A-Za-z0-9_-]+$"))))' <<< "$task_input") || {
        echo "Task input must contain a valid checkPrefixes array" >&2
        exit 64
      }
      selected_checks=$(jq -cn --argjson available "$selected_checks" --argjson prefixes "$check_prefixes" '
        [$available[]
          | . as $check
          | select(any($prefixes[]; . as $prefix
            | ($prefix == "*" or ($check | startswith($prefix)))))]')
      if [[ $(jq 'length' <<< "$selected_checks") -eq 0 ]]; then
        echo "No checks matched the selected prefixes; falling back to the full '$group' group" >&2
        selected_checks=$(filter_for_group "$group")
      fi
    fi

    matrix=$(jq -cn --argjson checks "$selected_checks" --argjson size "$batch_size" \
      '{include: [range(0; ($checks | length); $size) as $start | {checks: $checks[$start:($start + $size)]}]}')
    if [[ -n "${DEVENV_TASK_OUTPUT_FILE:-}" ]]; then
      printf '{"matrix":%s}\n' "$matrix" > "$DEVENV_TASK_OUTPUT_FILE"
    fi
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      printf 'matrix=%s\n' "$matrix" >> "$GITHUB_OUTPUT"
    fi
    printf 'Selected %s check matrix: %s\n' "$group" "$matrix"
    ;;
  build)
    max_jobs="${NIX_MAX_JOBS:-$(jq -r '.maxJobs // 2' <<< "$task_input")}"
    if [[ ! "$max_jobs" =~ ^[1-9][0-9]*$ ]]; then
      echo "maxJobs must be a positive integer (got '$max_jobs')" >&2
      exit 64
    fi

    if jq -e 'has("checks")' <<< "$task_input" >/dev/null; then
      checks=$(jq -ce '.checks | select(type == "array" and length > 0 and all(.[]; type == "string" and test("^[A-Za-z0-9_-]+$")))' <<< "$task_input") || {
        echo "Task input must contain a non-empty checks array" >&2
        exit 64
      }
      while IFS= read -r check; do
        if ! jq -e --arg check "$check" 'index($check) != null' <<< "$selected_checks" >/dev/null; then
          echo "Check '$check' is not selected for the '$group' group" >&2
          exit 64
        fi
      done < <(jq -r '.[]' <<< "$checks")
    else
      checks="$selected_checks"
    fi

    mapfile -t check_names < <(jq -r '.[]' <<< "$checks")
    installables=()
    for check in "${check_names[@]}"; do
      installables+=(".#checks.${current_system}.${check}")
    done

    echo "Building ${#installables[@]} '$group' checks on $current_system (max-jobs: $max_jobs)"
    "$nix_bin" build --no-link --max-jobs "$max_jobs" "${installables[@]}"
    ;;
  *) usage ;;
esac
