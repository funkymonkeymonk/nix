#!/usr/bin/env bash
# Test: Superpowers skills migration
set -euo pipefail

echo "Testing skills migration..."

# Check if skills directory exists in repository
test -d modules/home-manager/agent-skills/skills && echo "Skills directory exists" || echo "FAIL: Skills directory missing"

# Check if skills are present
if find modules/home-manager/agent-skills/skills -name "SKILL.md" | head -1 | grep -q .; then
    echo "Skills found"
else
    echo "FAIL: No skills found"
fi

echo "Expected skills directory with migrated skills"