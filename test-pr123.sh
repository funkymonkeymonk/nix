#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing PR #123: LiteLLM and Ollama Services ==="
echo ""

OLLAMA_HOST="${OLLAMA_HOST:-localhost}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_HOST="${LITELLM_HOST:-localhost}"
LITELLM_PORT="${LITELLM_PORT:-4000}"

# Test 1: Check if Ollama is installed
echo "[1/6] Checking if Ollama is installed..."
if command -v ollama &>/dev/null; then
    echo "  ✓ Ollama installed: $(ollama --version)"
else
    echo "  ✗ Ollama not found in PATH"
    exit 1
fi

# Test 2: Check if Ollama port is listening
echo "[2/6] Checking if Ollama is listening on port $OLLAMA_PORT..."
if nc -z "$OLLAMA_HOST" "$OLLAMA_PORT" 2>/dev/null || timeout 2 bash -c "echo >/dev/tcp/$OLLAMA_HOST/$OLLAMA_PORT" 2>/dev/null; then
    echo "  ✓ Ollama port $OLLAMA_PORT is open"
else
    echo "  ✗ Ollama port $OLLAMA_PORT not reachable"
    exit 1
fi

# Test 3: Test Ollama API health
echo "[3/6] Testing Ollama API..."
OLLAMA_RESPONSE=$(curl -s --max-time 5 "http://$OLLAMA_HOST:$OLLAMA_PORT/api/tags" || echo "failed")
if echo "$OLLAMA_RESPONSE" | grep -q "models"; then
    echo "  ✓ Ollama API responding"
    echo "  Available models:"
    echo "$OLLAMA_RESPONSE" | jq -r '.models[].name' 2>/dev/null | sed 's/^/    - /' || echo "$OLLAMA_RESPONSE"
else
    echo "  ✗ Ollama API not responding correctly"
    exit 1
fi

# Test 4: Check if LiteLLM is installed
echo "[4/6] Checking if LiteLLM is installed..."
if command -v litellm &>/dev/null; then
    echo "  ✓ LiteLLM installed"
else
    echo "  ✗ LiteLLM not found in PATH"
    exit 1
fi

# Test 5: Check if LiteLLM port is listening
echo "[5/6] Checking if LiteLLM is listening on port $LITELLM_PORT..."
if nc -z "$LITELLM_HOST" "$LITELLM_PORT" 2>/dev/null || timeout 2 bash -c "echo >/dev/tcp/$LITELLM_HOST/$LITELLM_PORT" 2>/dev/null; then
    echo "  ✓ LiteLLM port $LITELLM_PORT is open"
else
    echo "  ✗ LiteLLM port $LITELLM_PORT not reachable"
    exit 1
fi

# Test 6: Test LiteLLM API
echo "[6/6] Testing LiteLLM API..."
LITELLM_HEALTH=$(curl -s --max-time 5 "http://$LITELLM_HOST:$LITELLM_PORT/health" || echo "failed")
if echo "$LITELLM_HEALTH" | grep -qi "healthy\|{}"; then
    echo "  ✓ LiteLLM health endpoint responding"
else
    echo "  ✗ LiteLLM health check failed: $LITELLM_HEALTH"
    exit 1
fi

# Bonus: List LiteLLM models
echo ""
echo "[Bonus] Listing LiteLLM models..."
LITELLM_MODELS=$(curl -s --max-time 5 "http://$LITELLM_HOST:$LITELLM_PORT/v1/models" || echo "failed")
if echo "$LITELLM_MODELS" | grep -q "data"; then
    echo "  Available models:"
    echo "$LITELLM_MODELS" | jq -r '.data[].id' 2>/dev/null | sed 's/^/    - /' || echo "$LITELLM_MODELS"
fi

echo ""
echo "=== All tests passed ==="
echo ""
echo "Services are running:"
echo "  - Ollama: http://$OLLAMA_HOST:$OLLAMA_PORT"
echo "  - LiteLLM: http://$LITELLM_HOST:$LITELLM_PORT"
