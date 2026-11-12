#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [[ -n "${DEVENV_TASK_INPUT:-}" ]]; then
  task_input="$DEVENV_TASK_INPUT"
else
  task_input='{}'
fi
selection=$(jq -er '(.machine // "") | if type == "string" then . else error("machine must be a string") end' <<< "$task_input")
chart_expression=$(nix eval --impure --option builders "" --raw --file ./library/machines/chart-expression.nix)
all_machines=$(MACHINE_CHART_ACTION=names nix eval --impure --option builders "" --raw --expr "$chart_expression")

if [[ -n "$selection" ]]; then
  machine_rows=$(jq -r --arg selected "$selection" '
    .[] | select(.name | ascii_downcase == ($selected | ascii_downcase)) | [.kind, .name] | @tsv
  ' <<< "$all_machines")
  if [[ -z "$machine_rows" ]]; then
    available=$(jq -r '[.[].name] | join(", ")' <<< "$all_machines")
    echo "Unknown machine '$selection'. Available machines: $available" >&2
    exit 1
  fi
  if [[ $(wc -l <<< "$machine_rows") -gt 1 ]]; then
    echo "Machine name '$selection' is ambiguous across configurations" >&2
    exit 1
  fi
else
  machine_rows=$(jq -r '.[] | [.kind, .name] | @tsv' <<< "$all_machines")
fi

failed=0
first=true
while IFS=$'\t' read -r kind name; do
  [[ -z "$name" ]] && continue
  error_file=$(mktemp)
  if chart=$(MACHINE_CHART_ACTION=chart MACHINE_CHART_KIND="$kind" MACHINE_CHART_NAME="$name" MACHINE_CHART_PACKAGES=true nix eval --impure --option builders "" --raw --expr "$chart_expression" 2>"$error_file"); then
    :
  else
    if grep -qi 'platform mismatch' "$error_file"; then
      package_note="Nix needs a builder matching this target platform."
    else
      package_note="Nix could not evaluate this machine's package list."
    fi
    if ! chart=$(MACHINE_CHART_ACTION=chart MACHINE_CHART_KIND="$kind" MACHINE_CHART_NAME="$name" MACHINE_CHART_PACKAGES=false MACHINE_CHART_PACKAGE_NOTE="$package_note" nix eval --impure --option builders "" --raw --expr "$chart_expression" 2>"$error_file"); then
      echo "$name: unable to evaluate machine chart:" >&2
      cat "$error_file" >&2
      rm -f "$error_file"
      failed=1
      continue
    fi
  fi
  rm -f "$error_file"
  if [[ "$first" == true ]]; then
    first=false
  else
    printf '\n'
  fi
  printf '%s\n' "$chart"
done <<< "$machine_rows"

exit "$failed"
