#!/usr/bin/env bash
# Integration test for complete jj-finish workflow
# Tests the orchestration of all components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.bash"

echo "=== Integration Test: jj-finish workflow ==="
echo ""

# Setup test environment
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

echo -e "${TEST_BLUE}Setting up test repository...${TEST_NC}"

# Initialize jj repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
jj git init --colocate 2>/dev/null || true
git remote add origin 'https://github.com/test/repo.git'

# Create initial commit
echo "initial" > README.md
jj describe -m "Initial commit" 2>/dev/null || true

# Create a feature branch
jj new 2>/dev/null || true
echo "feature code" > feature.txt
jj bookmark set feat/test-feature -r @ 2>/dev/null || true

# Setup mock commands
mkdir -p "$TEST_DIR/bin"

# Mock gh command
cat > "$TEST_DIR/bin/gh" << 'MOCKGH'
#!/bin/bash
case "$1" in
    pr)
        case "$2" in
            view)
                # Simulate PR exists
                echo '{"number": 42, "url": "https://github.com/test/repo/pull/42"}'
                exit 0
                ;;
            create)
                echo "https://github.com/test/repo/pull/42"
                exit 0
                ;;
            merge)
                echo "Merged"
                exit 0
                ;;
            checks)
                # Simulate passing checks
                echo '[{"name": "test", "state": "SUCCESS"}]'
                exit 0
                ;;
        esac
        ;;
    run)
        echo '[]'
        exit 0
        ;;
esac
exit 0
MOCKGH
chmod +x "$TEST_DIR/bin/gh"

# Mock watch-ci-jobs (simulates passing)
cat > "$TEST_DIR/bin/watch-ci-jobs" << 'MOCKWATCH'
#!/bin/bash
echo "Monitoring CI..."
echo "All checks passed!"
exit 0
MOCKWATCH
chmod +x "$TEST_DIR/bin/watch-ci-jobs"

# Mock jj-pr
cat > "$TEST_DIR/bin/jj-pr" << 'MOCKPR'
#!/bin/bash
echo "Creating PR..."
exit 0
MOCKPR
chmod +x "$TEST_DIR/bin/jj-pr"

# Mock jj-push
cat > "$TEST_DIR/bin/jj-push" << 'MOCKPUSH'
#!/bin/bash
echo "Pushing bookmark..."
exit 0
MOCKPUSH
chmod +x "$TEST_DIR/bin/jj-push"

# Mock jj-pr-merge
cat > "$TEST_DIR/bin/jj-pr-merge" << 'MOCKMERGE'
#!/bin/bash
echo "Merging PR..."
exit 0
MOCKMERGE
chmod +x "$TEST_DIR/bin/jj-pr-merge"

export PATH="$TEST_DIR/bin:$PATH"

echo -e "${TEST_BLUE}Running integration tests...${TEST_NC}"
echo ""

# Test 1: Dry run shows all steps
run_test "Dry run shows workflow steps" "
    $SCRIPT_DIR/../scripts/jj-finish --dry-run 2>&1 | grep -q 'DRY RUN'
"

# Test 2: Help shows orchestration info
run_test "Help shows orchestration details" "
    $SCRIPT_DIR/../scripts/jj-finish --help 2>&1 | grep -q 'Orchestrates'
"

# Test 3: Finish detects repository
run_test "Finish detects jj repository" "
    OUTPUT=$($SCRIPT_DIR/../scripts/jj-finish --dry-run 2>&1)
    echo '$OUTPUT' | grep -q 'Repository:'
"

# Test 4: Finish detects bookmark
run_test "Finish detects bookmark" "
    OUTPUT=$($SCRIPT_DIR/../scripts/jj-finish --dry-run 2>&1)
    echo '$OUTPUT' | grep -q 'feat/test-feature'
"

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo ""
report_results
