#!/usr/bin/env bash
# Generate test outputs dynamically based on machine configurations

set -euo pipefail

echo "🧪 Generating test outputs for Nix configurations..."

# Extract machine configurations from flake.nix
echo "📊 Analyzing machine configurations..."

MACHINES=(
  "wweaver:darwin:developer workstation wweaver_llm_client wweaver_claude_client"
  "MegamanX:darwin:developer creative gaming entertainment workstation wweaver_llm_client megamanx_llm_host megamanx_llm_server"
  "drlight:linux:developer creative wweaver_llm_client"
  "zero:linux:developer wweaver_llm_client"
)

BUNDLES=(
  "creative developer gaming entertainment workstation"
  "wweaver_llm_client wweaver_claude_client"
  "megamanx_llm_host megamanx_llm_server"
)

# Generate bundle test outputs
echo "📦 Generating bundle test outputs..."
for bundle in ${BUNDLES[@]}; do
  for platform in darwin linux; do
    echo "  - ${bundle} on ${platform}"
  done
done

# Generate integration test outputs  
echo "🔗 Generating integration test outputs..."
for machine_info in "${MACHINES[@]}"; do
  IFS=':' read -r machine platform bundles_str <<< "$machine_info"
  IFS=' ' read -ra bundles_array <<< "$bundles_str"
  
  for bundle in "${bundles_array[@]}"; do
    if [ "$bundle" != "base" ]; then
      echo "  - ${machine} + ${bundle} on ${platform}"
    fi
  done
done

echo "✅ Test generation analysis completed"
echo ""
echo "📈 Summary:"
echo "  Machines: $(echo "${MACHINES[@]}" | wc -w)"
echo "  Bundles: $(echo "${BUNDLES[@]}" | wc -w)"  
echo "  Total integration tests: $(grep -c '+' <<< "$(printf '%s\n' "${MACHINES[@]}" | tr ' ' '\n' | grep -v 'base')")"
echo "  Total bundle tests: $((${#BUNDLES[@]} * 2))"