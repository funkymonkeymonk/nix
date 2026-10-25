#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
status_helpers="$repo_root/tests/lib/machines-e2e-status.sh"

if [[ ! -f "$status_helpers" ]]; then
  echo "machines e2e status: missing status acceptance helper" >&2
  exit 1
fi

source "$status_helpers"

for phase in awaiting-confirmation pending rolled-back failed rollback-failed unknown; do
  if machines_e2e_status_is_success "$phase"; then
    echo "machines e2e status: incorrectly accepted '$phase' as success" >&2
    exit 1
  fi
done

if ! machines_e2e_status_is_success succeeded; then
  echo "machines e2e status: did not accept terminal 'succeeded'" >&2
  exit 1
fi

echo "machines e2e status: only terminal succeeded is accepted"
