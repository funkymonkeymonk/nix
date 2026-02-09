#!/usr/bin/env bash
#
# LiteLLM Setup Test Script
# Tests if LiteLLM is properly configured and running
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Configuration
LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_HOST="${LITELLM_HOST:-localhost}"
LITELLM_CONFIG="${LITELLM_CONFIG:-$HOME/.config/litellm/config.yaml}"

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++)) || true
}

skip() {
    echo -e "${YELLOW}⊘${NC} $1"
    ((TESTS_SKIPPED++)) || true
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Test 1: Check if litellm command is available
test_litellm_installed() {
    echo -e "\n${BLUE}=== Testing LiteLLM Installation ===${NC}"
    if command -v litellm &> /dev/null; then
        local version
        version=$(litellm --version 2>/dev/null || echo "unknown")
        pass "LiteLLM is installed (version: $version)"
    else
        fail "LiteLLM is not installed or not in PATH"
        info "Install with: nix-shell -p python3Packages.litellm"
    fi
}

# Test 2: Check Python dependencies
test_python_deps() {
    echo -e "\n${BLUE}=== Testing Python Dependencies ===${NC}"
    local deps=("fastapi" "uvicorn" "pyyaml" "pydantic" "requests" "openai")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if python3 -c "import $dep" 2>/dev/null; then
            pass "Python module '$dep' is available"
        else
            fail "Python module '$dep' is missing"
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        info "Missing dependencies can be installed via Nix"
    fi
}

# Test 3: Check configuration file
test_config_file() {
    echo -e "\n${BLUE}=== Testing Configuration File ===${NC}"
    
    # Check if config exists in common locations
    local configs=(
        "$HOME/.config/litellm/config.yaml"
        "/etc/litellm/config.yaml"
        "./configs/litellm/config.yaml"
        "./config.yaml"
    )
    
    local config_found=""
    for config in "${configs[@]}"; do
        if [ -f "$config" ]; then
            config_found="$config"
            break
        fi
    done
    
    if [ -n "$config_found" ]; then
        pass "Configuration file found at: $config_found"
        
        # Validate YAML syntax
        if python3 -c "import yaml; yaml.safe_load(open('$config_found'))" 2>/dev/null; then
            pass "Configuration file is valid YAML"
        else
            fail "Configuration file has invalid YAML syntax"
        fi
        
        # Check for required sections
        if grep -q "model_list:" "$config_found" 2>/dev/null; then
            pass "Configuration has model_list section"
        else
            fail "Configuration missing model_list section"
        fi
        
        if grep -q "general_settings:" "$config_found" 2>/dev/null; then
            pass "Configuration has general_settings section"
        fi
    else
        fail "No configuration file found"
        info "Searched locations: ${configs[*]}"
    fi
}

# Test 4: Check environment variables
test_environment() {
    echo -e "\n${BLUE}=== Testing Environment Variables ===${NC}"
    
    # Check for master key
    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
        pass "LITELLM_MASTER_KEY is set"
    else
        # Check 1Password CLI with timeout
        if command -v op &> /dev/null; then
            # Quick check if op is signed in (with timeout)
            if timeout 5 op account list &> /dev/null; then
                pass "1Password CLI is available and authenticated"
                info "LiteLLM can retrieve master key from 1Password"
            else
                skip "1Password CLI available but not authenticated"
                info "Run: op signin to authenticate"
            fi
        else
            skip "LITELLM_MASTER_KEY not set and 1Password CLI not found"
            info "Set LITELLM_MASTER_KEY or install 1Password CLI"
        fi
    fi
    
    # Check for provider API keys
    local providers=("OPENAI_API_KEY" "ANTHROPIC_API_KEY" "AZURE_API_KEY" "OLLAMA_API_KEY")
    local has_provider_key=false
    
    for provider in "${providers[@]}"; do
        if [ -n "${!provider:-}" ]; then
            pass "$provider is set"
            has_provider_key=true
        fi
    done
    
    if [ "$has_provider_key" = false ]; then
        skip "No LLM provider API keys found in environment"
        info "At least one provider key is needed for LiteLLM to work"
    fi
}

# Test 5: Check systemd service (Linux only)
test_systemd_service() {
    echo -e "\n${BLUE}=== Testing Systemd Service ===${NC}"
    
    if [ "$(uname)" != "Linux" ]; then
        skip "Systemd service check skipped (not on Linux)"
        return
    fi
    
    if command -v systemctl &> /dev/null; then
        # Check user service
        if timeout 2 systemctl --user is-enabled litellm &> /dev/null; then
            pass "LiteLLM user service is enabled"
        else
            skip "LiteLLM user service is not enabled"
        fi
        
        if timeout 2 systemctl --user is-active litellm &> /dev/null; then
            pass "LiteLLM user service is running"
        else
            skip "LiteLLM user service is not running"
            info "Start with: systemctl --user start litellm"
        fi
    else
        skip "systemctl not found, skipping systemd checks"
    fi
}

# Test 6: Check if server is responding
test_server_running() {
    echo -e "\n${BLUE}=== Testing LiteLLM Server ===${NC}"
    
    local url="http://${LITELLM_HOST}:${LITELLM_PORT}"
    local server_up=false
    
    # Test basic connectivity with timeout
    if timeout 3 curl -sf "${url}/health" &> /dev/null; then
        pass "LiteLLM server health endpoint responding on port $LITELLM_PORT"
        server_up=true
    elif timeout 3 curl -sf "${url}/health/liveliness" &> /dev/null; then
        pass "LiteLLM server liveliness endpoint responding on port $LITELLM_PORT"
        server_up=true
    elif timeout 3 bash -c "exec 3<>/dev/tcp/${LITELLM_HOST}/${LITELLM_PORT}" 2>/dev/null; then
        pass "LiteLLM server is accepting connections on port $LITELLM_PORT"
        server_up=true
    else
        fail "LiteLLM server is not responding on port $LITELLM_PORT"
        info "Start the server with: litellm --config config.yaml"
    fi
    
    # Test models endpoint if server is up and we have API key
    if [ "$server_up" = true ] && [ -n "${LITELLM_MASTER_KEY:-}" ]; then
        local response
        response=$(timeout 5 curl -sf "${url}/v1/models" \
            -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || echo "")
        if [ -n "$response" ]; then
            pass "Models endpoint is accessible"
            info "Available models:"
            echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); [print(f'  - {m[\"id\"]}') for m in data.get('data', [])]" 2>/dev/null || true
        else
            skip "Could not query models endpoint (check API key)"
        fi
    elif [ "$server_up" = true ]; then
        skip "Skipping authenticated endpoint tests (no API key)"
    fi
}

# Test 7: Configuration dry-run
test_config_dryrun() {
    echo -e "\n${BLUE}=== Testing Configuration Dry-Run ===${NC}"
    
    if ! command -v litellm &> /dev/null; then
        skip "Cannot run dry-run test (litellm not installed)"
        return
    fi
    
    # Find config file
    local config=""
    for c in "$HOME/.config/litellm/config.yaml" "/etc/litellm/config.yaml" "./configs/litellm/config.yaml"; do
        if [ -f "$c" ]; then
            config="$c"
            break
        fi
    done
    
    if [ -n "$config" ]; then
        # Note: LiteLLM doesn't have a --dry-run flag, but we can validate the config
        pass "Configuration file exists for validation"
        info "Config location: $config"
        
        # Try to validate using Python
        if python3 -c "
import yaml
import sys
try:
    with open('$config', 'r') as f:
        cfg = yaml.safe_load(f)
    if 'model_list' in cfg:
        print(f'Found {len(cfg[\"model_list\"])} models in config')
        sys.exit(0)
    else:
        print('Warning: model_list not found in config')
        sys.exit(0)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>/dev/null; then
            pass "Configuration structure appears valid"
        else
            fail "Configuration validation failed"
        fi
    else
        skip "No config file found for dry-run validation"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        ${YELLOW}LiteLLM Configuration Test Suite${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Run all tests
    test_litellm_installed
    test_python_deps
    test_config_file
    test_environment
    test_systemd_service
    test_server_running
    test_config_dryrun
    
    # Summary
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✓ All critical tests passed!${NC}"
        if [ $TESTS_SKIPPED -gt 0 ]; then
            echo -e "${YELLOW}Note: Some optional checks were skipped${NC}"
        fi
        exit 0
    else
        echo -e "\n${RED}✗ Some tests failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
