#!/usr/bin/env bash
# Unit tests for jj-push

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helper.bash"

echo "=== Testing jj-push ==="
echo ""

# Test 1: Help flag
run_test "Help flag displays usage" "
    $SCRIPT_DIR/../scripts/jj-push --help | grep -q 'Usage: jj-push'
"

# Test 2: Dry run mode shows output without executing
run_test "Dry run mode shows preview" "
    # Create temp test dir
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR
    
    # Initialize jj repo
    git init -q
    jj git init --colocate 2>/dev/null || true
    git remote add origin 'https://github.com/test/repo.git'
    
    # Create bookmark
    echo 'test' > file.txt
    jj bookmark set test-branch -r @ 2>/dev/null || true
    
    # Run dry-run and check output
    OUTPUT=$($SCRIPT_DIR/../scripts/jj-push --dry-run 2>&1)
    echo "$OUTPUT" | grep -q 'DRY RUN'
    
    # Cleanup
    cd /
    rm -rf $TEST_DIR
"

# Test 3: Error when not in jj repo
run_test "Error when not in jj repo" "
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR
    
    # Run without jj repo - should fail
    if $SCRIPT_DIR/../scripts/jj-push 2>&1 | grep -q 'Not in a jj repository'; then
        cd /
        rm -rf $TEST_DIR
        exit 0
    else
        cd /
        rm -rf $TEST_DIR
        exit 1
    fi
"

# Test 4: Error when no bookmark
run_test "Error when no bookmark" "
    TEST_DIR=$(mktemp -d)
    cd $TEST_DIR
    
    # Initialize but don't create bookmark
    git init -q
    jj git init --colocate 2>/dev/null || true
    git remote add origin 'https://github.com/test/repo.git'
    
    # Should fail with no bookmark
    if $SCRIPT_DIR/../scripts/jj-push 2>&1 | grep -q 'No bookmark found'; then
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
