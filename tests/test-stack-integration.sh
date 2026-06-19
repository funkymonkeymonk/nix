#!/usr/bin/env bash
# Integration test for the LLM stack (vMLX + Bifrost + Caddy + dnsmasq).
# Validates that all layers are running and the full chain works.
# Usage: ./tests/test-stack-integration.sh [--verbose]
set -euo pipefail

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

PASS=0; FAIL=0; WARN=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $*"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $*"; }
warn() { WARN=$((WARN+1)); echo -e "  ${YELLOW}⚠${NC} $*"; }
info() { echo -e "  ${CYAN}→${NC} $*"; }

check_dns() {
  local host=$1 expected=$2
  local resolved
  resolved=$(dig +short "$host" @"$3" 2>/dev/null || dscacheutil -q host -a name "$host" 2>/dev/null | grep ip_address | awk '{print $2}')
  if echo "$resolved" | grep -q "$expected"; then
    pass "$host resolves to $expected"
  else
    fail "$host resolves to $resolved (expected $expected)"
  fi
}

check_port() {
  local port=$1 name=$2
  if lsof -tiTCP -sTCP:LISTEN:"$port" -P 2>/dev/null; then
    pass "$name on port $port"
  else
    fail "$name NOT on port $port"
  fi
}

check_api() {
  local url=$1 label=$2
  local result
  result=$(curl -sf --max-time 10 "$url" 2>&1) || true
  if [ -n "$result" ]; then
    pass "$label responds"
    $VERBOSE && info "  Response: $(echo "$result" | head -c 200)"
  else
    fail "$label did not respond"
  fi
}

check_chat() {
  local url=$1 model=$2 label=$3
  local result
  result=$(curl -sf --max-time 60 "$url/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" 2>&1) || true
  if echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['choices']) > 0" 2>/dev/null; then
    local content
    content=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])")
    pass "$label chat: \"$content\""
  else
    fail "$label chat failed"
    $VERBOSE && info "  Response: $(echo "$result" | head -c 200)"
  fi
}

check_embedding() {
  local url=$1 model=$2 label=$3
  local result
  result=$(curl -sf --max-time 30 "$url/v1/embeddings" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"input\":\"Hello world\"}" 2>&1) || true
  if echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['data'][0]['embedding']) > 0" 2>/dev/null; then
    local dims
    dims=$(echo "$result" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data'][0]['embedding']))")
    pass "$label embedding: $dims dims"
  else
    fail "$label embedding failed"
    $VERBOSE && info "  Response: $(echo "$result" | head -c 200)"
  fi
}

echo "============================================"
echo "  LLM Stack Integration Tests"
echo "============================================"
echo ""

# Layer 0: DNS
echo "--- Layer 0: DNS ---"
check_dns "vmlx.internal" "127.0.0.1" "127.0.0.1"
check_dns "bifrost.internal" "127.0.0.1" "127.0.0.1"
check_dns "vane.internal" "127.0.0.1" "127.0.0.1"
echo ""

# Layer 1: Caddy + Ports
echo "--- Layer 1: Reverse Proxy ---"
check_port "5353" "dnsmasq"
check_port "80" "Caddy"
check_port "8300" "vMLX"
check_port "8081" "Bifrost"
check_port "3000" "Vane"
echo ""

# Layer 2: vMLX
echo "--- Layer 2: vMLX ---"
check_api "http://localhost:8300/v1/models" "vMLX /v1/models"
check_chat "http://localhost:8300" "mlx-community/gemma-4-12B-it-OptiQ-4bit" "vMLX"
check_embedding "http://localhost:8300" "mlx-community/nomicai-modernbert-embed-base-4bit" "vMLX"
echo ""

# Layer 3: Bifrost
echo "--- Layer 3: Bifrost ---"
check_api "http://localhost:8081/v1/models" "Bifrost /v1/models"
check_chat "http://localhost:8081" "mlx-community/gemma-4-12B-it-OptiQ-4bit" "Bifrost"
check_embedding "http://localhost:8081" "mlx-community/nomicai-modernbert-embed-base-4bit" "Bifrost"
echo ""

# Layer 4: Caddy routing
echo "--- Layer 4: Caddy Routing ---"
check_api "http://vmlx.internal/v1/models" "Caddy → vMLX"
check_api "http://bifrost.internal/v1/models" "Caddy → Bifrost"
check_api "http://vane.internal/" "Caddy → Vane"
check_chat "http://vmlx.internal" "mlx-community/gemma-4-12B-it-OptiQ-4bit" "Caddy → vMLX"
check_chat "http://bifrost.internal" "mlx-community/gemma-4-12B-it-OptiQ-4bit" "Caddy → Bifrost"
check_embedding "http://bifrost.internal" "mlx-community/nomicai-modernbert-embed-base-4bit" "Caddy → Bifrost"
echo ""

# Layer 5: Vane
echo "--- Layer 5: Vane ---"
check_api "http://localhost:3000/" "Vane UI"
if curl -sf --max-time 5 "http://localhost:3000/api/config" 2>/dev/null; then
  pass "Vane /api/config accessible"
fi
echo ""

echo "============================================"
echo "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
echo "============================================"
[ "$FAIL" -eq 0 ] || exit 1
