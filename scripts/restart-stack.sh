#!/usr/bin/env bash
# Restart the LLM stack in the correct order with proper port management.
# Usage: sudo ./scripts/restart-stack.sh [--force]
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }

PORTS=(5353 80 8300 8081 3000)
SERVICES=(
  "dnsmasq:com.dnsmasq.service"
  "caddy:com.caddy.service"
  "vmlx:org.vmlx.server"
  "bifrost:com.bifrost.service"
  "vane:com.vane.service"
)

wait_for_port_free() {
  local port=$1 label=$2 max_wait=${3:-15}
  local waited=0
  while lsof -tiTCP -sTCP:LISTEN:"$port" -P 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [ "$waited" -ge "$max_wait" ]; then
      err "$label port $port still bound after ${max_wait}s — killing any process"
      lsof -tiTCP -sTCP:LISTEN:"$port" -P 2>/dev/null | xargs kill -9 2>/dev/null || true
      sleep 2
      return 0
    fi
  done
}

wait_for_port() {
  local port=$1 label=$2 max_wait=${3:-30}
  local waited=0
  while ! lsof -tiTCP -sTCP:LISTEN:"$port" -P 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [ "$waited" -ge "$max_wait" ]; then
      err "$label not on port $port after ${max_wait}s"
      return 1
    fi
  done
  ok "$label ready on port $port"
}

restart_service() {
  local label=$1 port=$2 name=$3
  info "Stopping $name..."
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || sudo launchctl bootout system/"$label" 2>/dev/null || true
  wait_for_port_free "$port" "$name"
  info "Starting $name..."
  if launchctl bootstrap "gui/$(id -u)" /Library/LaunchDaemons/"$label".plist 2>/dev/null; then
    :
  else
    sudo launchctl bootstrap system /Library/LaunchDaemons/"$label".plist 2>/dev/null || true
  fi
}

restart_root_service() {
  local label=$1 port=$2 name=$3
  info "Stopping $name..."
  sudo launchctl bootout system/"$label" 2>/dev/null || true
  wait_for_port_free "$port" "$name"
  info "Starting $name..."
  sudo launchctl bootstrap system /Library/LaunchDaemons/"$label".plist 2>/dev/null || true
}

verify_service() {
  local url=$1 label=$2
  if curl -sf --max-time 5 "$url" >/dev/null 2>&1; then
    ok "$label — responding"
  else
    warn "$label — not responding yet"
  fi
}

echo "============================================"
echo "  LLM Stack Restart"
echo "============================================"
echo ""

# Layer 0: DNS (dnsmasq) — root
restart_root_service "com.dnsmasq.service" "5353" "dnsmasq"
sleep 2
verify_service "http://vmlx.internal:5353" "DNS resolution"
echo ""

# Layer 1: Reverse proxy (Caddy) — root
restart_root_service "com.caddy.service" "80" "Caddy"
sleep 2
verify_service "http://vmlx.internal/v1/models" "Caddy → vMLX"
verify_service "http://bifrost.internal/v1/models" "Caddy → Bifrost"
echo ""

# Layer 2: Inference (vMLX)
restart_service "org.vmlx.server" "8300" "vMLX"
wait_for_port "8300" "vMLX" 60
verify_service "http://localhost:8300/v1/models" "vMLX API"
echo ""

# Layer 3: AI Gateway (Bifrost)
restart_service "com.bifrost.service" "8081" "Bifrost"
wait_for_port "8081" "Bifrost" 30
verify_service "http://localhost:8081/v1/models" "Bifrost API"
echo ""

# Layer 4: Applications (Vane)
restart_service "com.vane.service" "3000" "Vane"
wait_for_port "3000" "Vane" 30
verify_service "http://localhost:3000/" "Vane UI"
echo ""

echo "============================================"
echo "  Final Verification"
echo "============================================"
for port in "${PORTS[@]}"; do
  if lsof -tiTCP -sTCP:LISTEN:"$port" -P 2>/dev/null; then
    ok "Port $port in use"
  else
    warn "Port $port not bound"
  fi
done
echo ""
echo "Run 'scripts/test-stack-integration.sh' for full integration tests."
