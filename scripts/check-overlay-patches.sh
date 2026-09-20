#!/usr/bin/env bash
set -euo pipefail

overlay_file=${1:-overlays/default.nix}
report_file=${2:-overlay-repair-proposal.md}

mkdir -p "$(dirname "$report_file")"
{
  printf '%s\n\n' '## Overlay Repair Proposal'
  printf '%s\n\n' 'This report lists overlay patches that may need review after dependency updates.'
} > "$report_file"

matches=0
while IFS= read -r line; do
  matches=$((matches + 1))
  printf '%s\n' '- Review patch:' "$line" >> "$report_file"
done < <(awk '
  /substituteInPlace/ { in_patch = 1; patch = $0; next }
  in_patch {
    patch = patch " " $0
    if ($0 ~ /--replace-fail/) {
      print patch
      in_patch = 0
      patch = ""
    }
  }
' "$overlay_file")

if ((matches == 0)); then
  printf '%s\n' '- No replace-fail overlay patches found.' >> "$report_file"
fi

printf 'Found %d replace-fail overlay patch(es) in %s\n' "$matches" "$overlay_file"
