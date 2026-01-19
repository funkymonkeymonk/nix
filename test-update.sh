#!/usr/bin/env bash
# Test: Agent skills update mechanism
set -euo pipefail

echo "Testing update mechanism..."

# Check if update command exists
if task --list-all | grep -q "agent-skills:"; then
    echo "✓ Found agent-skills tasks"
    task --list-all | grep "agent-skills:"
else
    echo "✗ No agent-skills tasks found"
    exit 1
fi

# Check if upstream version tracking file exists
if [[ -f "modules/home-manager/agent-skills/.upstream-version" ]]; then
    echo "✓ Version tracking file exists"
    echo "Content: $(cat modules/home-manager/agent-skills/.upstream-version 2>/dev/null || echo 'empty')"
else
    echo "✗ No version tracking file found"
    exit 1
fi

# Check if update script would be available (it's provided by home-manager when enabled)
if command -v update-agent-skills >/dev/null 2>&1; then
    echo "✓ update-agent-skills command available"
else
    echo "⚠ update-agent-skills command not available (expected when home-manager not activated)"
fi

echo "All update mechanism checks passed!"