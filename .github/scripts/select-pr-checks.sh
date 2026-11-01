#!/usr/bin/env bash
set -euo pipefail

patterns=()
select_all=false

add() {
  patterns+=("$@")
}

select_for_path() {
  local path="$1"

  case "$path" in
    flake.nix|flake.lock|devenv.nix|devenv.lock|devenv.yaml|tests/default.nix|tests/stubs.nix|tests/nix-unit-tests.nix|modules/common/options.nix|.github/workflows/*|.github/scripts/*)
      select_all=true
      ;;
    docs/*|README.md|README|*.md)
      ;;
    tests/test-vector.nix|modules/nixos/vector.nix|modules/services/vector/*)
      add nixos-vector- type-server-log-aggregator vector-
      ;;
    tests/test-log-aggregator.nix|modules/nixos/loki.nix)
      add nixos-loki- nixos-vector- type-server-log-aggregator
      ;;
    tests/test-loki.nix|modules/services/loki/*)
      add loki- nixos-loki-
      ;;
    tests/test-observability.nix)
      add node-exporter- prometheus-
      ;;
    modules/services/node-exporter/*|modules/services/prometheus/*)
      add node-exporter- prometheus- grafana- phase4-darwin-server type-server-archetypes
      ;;
    tests/test-nixos-observability.nix|modules/nixos/prometheus.nix|modules/nixos/alertmanager.nix)
      add nixos-prometheus- nixos-node-exporter- nixos-alertmanager- type-server-observability type-observability-archetype central-observability
      ;;
    tests/test-alertmanager.nix|modules/services/alertmanager/*)
      add alertmanager- nixos-alertmanager-
      ;;
    tests/test-grafana.nix|modules/nixos/grafana.nix|modules/services/grafana/*)
      add grafana- nixos-grafana- type-observability-archetype central-observability
      ;;
    tests/test-server-archetypes.nix)
      add type-server-archetypes type-server-observability central-observability
      ;;
    tests/test-media-center-archetype.nix|modules/nixos/homepage.nix)
      add media-center-archetype drlight-media- type-server-archetypes
      ;;
    tests/test-zero.nix|targets/zero/*|modules/nixos/streaming.nix)
      add zero- phase3-zero drlight-media-storage
      ;;
    tests/test-phase2-cattle.nix)
      add phase2-cattle headless-server-users
      ;;
    tests/test-phase3-zero.nix)
      add phase3-zero
      ;;
    tests/test-phase4-darwin-server.nix)
      add phase4-darwin-server
      ;;
    tests/test-phase5-core-bootstrap.nix)
      add core-bootstrap
      ;;
    tests/test-coverage.nix)
      add module-coverage
      ;;
    tests/test-roles.nix)
      add all-role-tests
      ;;
    tests/test-vm-role-generator.nix)
      add vm-role-generator
      ;;
    tests/test-agent-option-ownership.nix)
      add agent-option-ownership
      ;;
    tests/test-agent-user.nix)
      add agent-user-
      ;;
    tests/test-bifrost.nix)
      add bifrost-
      ;;
    tests/test-caddy.nix|modules/services/caddy/*)
      add caddy- zero-sunshine-caddy-proxy media-center-archetype drlight-media-presentation
      ;;
    tests/test-claude-code.nix)
      add claude-code-
      ;;
    tests/test-cross-platform-guards.nix)
      add cross-platform-
      ;;
    tests/test-dev-base-migration.nix)
      add dev-base-migration
      ;;
    tests/test-docker.nix)
      add nixos-docker-config
      ;;
    tests/test-email.nix|tests/test-email-option-ownership.nix)
      add email-
      ;;
    tests/test-flake-module.nix)
      add flake-module-
      ;;
    tests/test-git-enable.nix)
      add git-
      ;;
    tests/test-home-manager.nix)
      add opencode- aerospace- shell-aliases switch-task workspace-switch
      ;;
    tests/test-installer-ready.nix|targets/installer-iso/*)
      add installer-ready
      ;;
    tests/test-jj-workspace-access.nix)
      add opencode-jj-workspace-access
      ;;
    tests/test-library.nix)
      add mk-darwin-system mk-nixos-system flake-module-
      ;;
    tests/test-machine-ops.nix)
      add machines-ops machines-secretspec-empty-profiles
      ;;
    tests/test-machines-foundation.nix)
      add machines-secret-profiles
      ;;
    tests/test-machines-inventory.nix)
      add machines-inventory observability-inventory
      ;;
    tests/test-mk-user.nix)
      add mk-user
      ;;
    tests/test-nix-unit-runner.nix)
      add nix-unit-runner
      ;;
    tests/test-nixos-modules.nix)
      add typed-attrs-options
      ;;
    tests/test-observability-inventory.nix|library/machines/observability-inventory.nix)
      add observability-inventory central-observability type-server-archetypes
      ;;
    tests/test-obsidian.nix)
      add obsidian-
      ;;
    tests/test-omlx.nix)
      add omlx-
      ;;
    tests/test-options-doc.nix|scripts/generate-options-doc.nix)
      add options-doc-
      ;;
    tests/test-overlay-packages.nix|overlays/*|packages/*)
      add overlay- core-packages foundation-packages config-validation
      ;;
    tests/test-packages.nix)
      add core-packages foundation-packages ste-linter-package config-validation foundation-options onepassword- zsh-enable-single-location bfcl-package-metadata
      ;;
    tests/test-llm-client.nix)
      add llm-client-
      ;;
    tests/test-lume.nix)
      add lume-
      ;;
    tests/test-pi.nix)
      add pi-
      ;;
    tests/test-searxng.nix)
      add searxng-
      ;;
    tests/test-sketchybar-removed.nix)
      add sketchybar-
      ;;
    tests/test-skills-option-ownership.nix)
      add skills-option-ownership
      ;;
    tests/test-skills-canonical-install.nix)
      add skills-canonical-
      ;;
    tests/test-skills.nix)
      add skills-
      ;;
    tests/test-switch-task.nix)
      add switch-task
      ;;
    tests/test-temporal.nix)
      add temporal-
      ;;
    tests/test-workspace-switch.nix)
      add workspace-switch
      ;;
    library/machines/catalog.nix|library/machines/modules.nix|library/machines/flake-parts.nix)
      add machines-inventory machines-secret-profiles observability-inventory machines-ops type-server-archetypes type-server-observability type-observability-archetype central-observability media-center-archetype drlight-media-
      ;;
    library/archetypes/*)
      add type-server-archetypes type-server-observability type-observability-archetype central-observability media-center-archetype phase4-darwin-server
      ;;
    targets/drlight/*)
      add media-center-archetype drlight-media- central-observability type-server-archetypes
      ;;
    targets/type-server/*|targets/type-server-arm/*)
      add type-server-archetypes type-server-observability type-server-log-aggregator central-observability
      ;;
    modules/nixos/media-config.nix|modules/nixos/media-storage.nix)
      add media-center-archetype drlight-media- zero-
      ;;
    modules/nixos/onepassword*.nix|modules/common/onepassword*.nix)
      add onepassword- zero-tailscale-
      ;;
    tests/test-*.nix)
      # Unknown test files may define checks with unrelated names. Run the full
      # non-VM suite rather than silently omitting their coverage.
      select_all=true
      ;;
    *.nix|*.lock|*.yaml|*.yml|*.sh|*.py|*.toml)
      # Unknown source or build logic can affect checks outside its directory.
      select_all=true
      ;;
    *)
      # Unknown non-document files are conservative full-suite changes.
      select_all=true
      ;;
  esac
}

if [[ "${1:-}" == "--all" ]]; then
  printf '["*"]\n'
  exit 0
elif (($# > 0)); then
  echo "Usage: $0 [--all] < changed-files.txt" >&2
  exit 64
fi

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  select_for_path "$path"
done

if [[ "$select_all" == true ]]; then
  printf '["*"]\n'
elif ((${#patterns[@]} == 0)); then
  printf '[]\n'
else
  printf '%s\n' "${patterns[@]}" | sort -u | jq -Rsc 'split("\n") | map(select(length > 0))'
fi
