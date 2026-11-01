#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

nix_bin="${NIX_BIN:-nix}"
curl_bin="${CURL_BIN:-curl}"
source_configs="${OVERLAY_SOURCE_CONFIGS:-nixosConfigurations.drlight nixosConfigurations.type-server-arm darwinConfigurations.wweaver}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
raw_sources="$TMP_DIR/sources.jsonl"
: > "$raw_sources"

read -r -a configs <<< "$source_configs"
for config in "${configs[@]}"; do
  echo "Collecting overlay source URLs from $config"
  "$nix_bin" eval --impure --json ".#${config}.pkgs" \
    --apply 'pkgs: import ./scripts/overlay-source-urls.nix { inherit pkgs; }' \
    | jq -c '.[]' >> "$raw_sources"
done

if [[ ! -s "$raw_sources" ]]; then
  echo "ERROR: no repo-managed overlay source URLs were discovered" >&2
  exit 1
fi

mapfile -t source_groups < <(
  jq -sc 'group_by([.package, .version, .urls]) | map({package: .[0].package, version: .[0].version, urls: .[0].urls})' "$raw_sources" \
    | jq -c '.[]'
)

if [[ "${#source_groups[@]}" -eq 0 ]]; then
  echo "ERROR: overlay source URL inventory is empty" >&2
  exit 1
fi

fetch() {
  "$curl_bin" --fail --silent --show-error --location \
    --retry 2 --retry-connrefused --connect-timeout 10 --max-time 30 "$@"
}

resolve_url() {
  local package="$1" version="$2" source_url="$3"
  local filename metadata_url metadata resolved_url

  case "$source_url" in
    http://*|https://*)
      printf '%s\n' "$source_url"
      ;;
    mirror://pypi/*)
      filename="${source_url##*/}"
      metadata_url="$(jq -rn --arg package "$package" --arg version "$version" \
        '"https://pypi.org/pypi/\($package)/\($version)/json"')"
      if ! metadata="$(fetch "$metadata_url")"; then
        echo "ERROR: cannot read PyPI release metadata for $package $version" >&2
        return 1
      fi
      if ! resolved_url="$(jq -er --arg filename "$filename" \
        '[.urls[] | select(.filename == $filename) | .url] | first // empty' \
        <<< "$metadata")"; then
        echo "ERROR: PyPI release $package $version has no artifact named $filename" >&2
        return 1
      fi
      printf '%s\n' "$resolved_url"
      ;;
    *)
      echo "ERROR: unsupported external source URL scheme for $package: $source_url" >&2
      return 1
      ;;
  esac
}

failures=0
for group in "${source_groups[@]}"; do
  package="$(jq -r '.package' <<< "$group")"
  version="$(jq -r '.version' <<< "$group")"
  mapfile -t urls < <(jq -r '.urls[]' <<< "$group")
  reachable=false

  for source_url in "${urls[@]}"; do
    if ! resolved_url="$(resolve_url "$package" "$version" "$source_url")"; then
      continue
    fi
    if fetch --head --output /dev/null "$resolved_url"; then
      echo "  OK: $package $version — $resolved_url"
      reachable=true
      break
    fi
    echo "  unavailable: $package $version — $resolved_url" >&2
  done

  if [[ "$reachable" != true ]]; then
    echo "FAIL: no upstream source URL is reachable for $package $version" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  echo "ERROR: $failures repo-managed overlay source(s) are unavailable" >&2
  exit 1
fi

echo "All repo-managed overlay source URLs are reachable"
