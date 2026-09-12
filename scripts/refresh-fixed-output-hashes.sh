#!/usr/bin/env bash
set -euo pipefail

manifest=${1:-.github/fixed-output-hashes.json}
max_attempts=${MAX_ATTEMPTS:-3}

if [ ! -f "$manifest" ]; then
  echo "ERROR: hash manifest not found: $manifest" >&2
  exit 1
fi

mapfile -t targets < <(jq -r '.targets[] | @base64' "$manifest")
if [ "${#targets[@]}" -eq 0 ]; then
  echo "ERROR: hash manifest contains no targets: $manifest" >&2
  exit 1
fi

for encoded_target in "${targets[@]}"; do
  target=$(printf '%s' "$encoded_target" | base64 --decode)
  name=$(jq -r '.name' <<< "$target")
  derivation_pattern=$(jq -r '.derivationPattern // ("^" + .name + "$" )' <<< "$target")
  build_target=$(jq -r '.buildTarget' <<< "$target")
  file=$(jq -r '.file' <<< "$target")
  start=$(jq -r '.start' <<< "$target")
  field=$(jq -r '.field' <<< "$target")
  bootstrap=$(jq -r '.bootstrap // "lib.fakeHash"' <<< "$target")
  build_log=$(mktemp)
  trap 'rm -f "$build_log"' EXIT
  built=false

  if [ ! -f "$file" ]; then
    echo "ERROR: hash target file not found: $file" >&2
    exit 1
  fi

  for attempt in $(seq 1 "$max_attempts"); do
    echo "Building $name (attempt $attempt/$max_attempts)..."
    if nix build "$build_target" --no-link --print-build-logs \
        2>&1 | tee "$build_log"; then
      built=true
      break
    fi

    mismatch=$(sed -nE \
      's/.*To correct the hash mismatch for ([^,]+), use "([^"]+)".*/\1|\2/p' \
      "$build_log" | sed -n '$p')
    if [ -z "$mismatch" ]; then
      if grep -Eq \
        "(npmDepsHash|vendorHash) is out of date|missing go.sum entry" \
        "$build_log"; then
        sed -i \
          -e "/$start/,/^[[:space:]]*});/ s|$field = .*;|$field = $bootstrap;|" \
          "$file"
        echo "Bootstrapped $name with lib.fakeHash"
        continue
      fi

      derivation=$(sed -nE \
        "s|.*fixed-output derivation '.*/[a-z0-9]{32}-(.*)\\.drv':|\\1|p" \
        "$build_log" | sed -n '$p')
      replacement_hash=$(sed -nE \
        's/.*got:[[:space:]]+(sha256-[^[:space:]]+).*/\1/p' \
        "$build_log" | sed -n '$p')
      if [ -n "$derivation" ] && [ -n "$replacement_hash" ]; then
        mismatch="$derivation|$replacement_hash"
      else
        echo "ERROR: $name failed without a recognized fixed-output hash" >&2
        exit 1
      fi
    fi

    derivation=${mismatch%%|*}
    replacement_hash=${mismatch#*|}
    if ! printf '%s\n' "$derivation" | grep -Eq "$derivation_pattern"; then
      echo "ERROR: expected $derivation_pattern but Nix reported $derivation" >&2
      exit 1
    fi

    sed -i \
      -e "/$start/,/^[[:space:]]*});/ {" \
      -e "s|$field = .*;|$field = \"$replacement_hash\";|" \
      -e '}' \
      "$file"

    if git diff --quiet -- "$file"; then
      echo "ERROR: could not update $field for $name in $file" >&2
      exit 1
    fi

    echo "Updated $name in $file"
  done

  if [ "$built" != true ]; then
    echo "ERROR: $name still fails after $max_attempts attempts" >&2
    exit 1
  fi
done
