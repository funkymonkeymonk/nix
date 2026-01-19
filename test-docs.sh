#!/usr/bin/env bash
# Test: Documentation completeness
set -euo pipefail

echo "Testing documentation..."

# Check if README mentions agent-skills
grep -q "agent-skills" README.md && echo "✓ README mentions agent-skills" || echo "FAIL: README missing agent-skills"

# Check if detailed documentation exists
test -f docs/agent-skills.md && echo "✓ Detailed documentation exists" || echo "FAIL: Detailed documentation missing"

echo "Expected comprehensive documentation"