#!/usr/bin/env bash
# Unit tests for jj-pr-merge

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.bash"

echo "=== Testing jj-pr-merge ==="
echo ""

# Test 1: Help flag
run_test "Help flag displays usage" "
    $SCRIPT_DIR/../scripts/jj-pr-merge --help | grep -q 'Usage: jj-pr-merge'
"

# Test 2: Dry run mode
run_test "Dry run mode shows preview" "
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR
    
    # Setup jj repo with mock gh
    git init -q
    jj git init --colocate 2>/dev/null || true
    git remote add origin 'https://github.com/test/repo.git'
    jj bookmark set test-branch -r @ 2>/dev/null || true
    
    # Create mock gh
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/gh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "view" ]]; then
    echo '{"number": 123, "url": "https://github.com/test/repo/pull/123"}'
fi
exit 0
MOCK
    chmod +x "$TEST_DIR/bin/gh"
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Run dry-run
    OUTPUT=$($SCRIPT_DIR/../scripts/jj-pr-merge --dry-run 2>&1)
    RESULT=$?
    
    cd /
    rm -rf $TEST_DIR
    
    echo "$OUTPUT" | grep -q 'DRY RUN'
"

# Test 3: Error when no PR exists
run_test "Error when no PR for branch" "
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR
    
    # Setup without PR
    git init -q
    jj git init --colocate 2>/dev/null || true
    git remote add origin 'https://github.com/test/repo.git'
    jj bookmark set orphan-branch -r @ 2>/dev/null || true
    
    # Mock gh that returns nothing
    mkdir -p "$TEST_DIR/bin"
    cat > "$TEST_DIR/bin/gh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$TEST_DIR/bin/gh"
    export PATH="$TEST_DIR/bin:$PATH"
    
    # Should fail
    if $SCRIPT_DIR/../scripts/jj-pr-merge 2>&1 | grep -q 'No PR found'; then
        cd /
        rm -rf $TEST_DIR
        exit 0
    else
        cd /
        rm -rf $TEST_DIR
        exit 1
    fi
"

echo ""
report_results
