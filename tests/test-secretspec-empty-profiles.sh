#!/usr/bin/env bash
set -euo pipefail

: "${SECRETSPEC_BIN:?set SECRETSPEC_BIN to the pinned devenv SecretSpec executable}"
: "${SECRETSPEC_MANIFEST:?set SECRETSPEC_MANIFEST to the repository secretspec.toml}"
: "${COREUTILS_BIN:?set COREUTILS_BIN to the coreutils bin directory}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/project"
cp "$SECRETSPEC_MANIFEST" "$tmp/project/secretspec.toml"

cat > "$tmp/bin/op" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >> '$tmp/op.log'
exit 97
EOF
cat > "$tmp/bin/child" <<EOF
#!/bin/sh
touch '$tmp/child-ran'
exec '$COREUTILS_BIN/env'
EOF
chmod +x "$tmp/bin/op" "$tmp/bin/child"

# Personal has no profile because it has no secrets; Homelab's approved opnix
# token reference is checked structurally in test-machine-ops.nix.
for profile in Personal; do
  if output=$(cd "$tmp/project" && env -i \
    HOME="$tmp/home" \
    PATH="$tmp/bin:$COREUTILS_BIN" \
    "$SECRETSPEC_BIN" run --profile "$profile" -- child 2>&1); then
    echo "SecretSpec unexpectedly accepted empty profile $profile" >&2
    printf '%s\\n' "$output" >&2
    exit 1
  fi

  [[ -n "$output" ]] || {
    echo "SecretSpec failed without an error for unconfigured profile $profile" >&2
    exit 1
  }
  [[ ! -e "$tmp/op.log" ]] || {
    echo "SecretSpec invoked the failing op stub for empty profile $profile" >&2
    cat "$tmp/op.log" >&2
    exit 1
  }
  [[ ! -e "$tmp/child-ran" ]] || {
    echo "SecretSpec ran the child command for invalid empty profile $profile" >&2
    exit 1
  }
done

printf 'SecretSpec empty-profile fail-closed tests passed\\n'
