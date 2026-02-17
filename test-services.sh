#!/usr/bin/env bash
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        ((PASS++)) || true
    else
        echo -e "${RED}✗${NC} $name"
        ((FAIL++)) || true
    fi
}

check_http() {
    local name="$1"
    local url="$2"
    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name ($url)"
        ((PASS++)) || true
    else
        echo -e "${RED}✗${NC} $name ($url)"
        ((FAIL++)) || true
    fi
}

echo "=== LLM Services Status ==="
echo

echo "--- Ollama ---"
check "Ollama process running" "pgrep -x ollama"
check_http "Ollama API responding" "http://localhost:11434/api/tags"

echo
echo "--- LiteLLM ---"
check "LiteLLM container running" "docker ps --filter name=litellm --format '{{.Names}}' | grep -q litellm"
check_http "LiteLLM API responding" "http://localhost:4000/health"

echo
echo "--- Observability Stack (LGTM) ---"
check "Loki container running" "docker ps --filter name=loki --format '{{.Names}}' | grep -q loki"
check_http "Loki API responding" "http://localhost:3100/ready"
check "Grafana container running" "docker ps --filter name=grafana --format '{{.Names}}' | grep -q grafana"
check_http "Grafana API responding" "http://localhost:3000/api/health"

echo
echo "--- Summary ---"
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${RED}Failed:${NC} $FAIL"

if [ $FAIL -gt 0 ]; then
    echo -e "\n${YELLOW}Some services are not running properly.${NC}"
    exit 1
else
    echo -e "\n${GREEN}All services are running!${NC}"
    exit 0
fi
