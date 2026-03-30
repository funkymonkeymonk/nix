#!/usr/bin/env bash
# Test helper library for jj workflow tests

# Colors for test output
TEST_RED='\033[0;31m'
TEST_GREEN='\033[0;32m'
TEST_YELLOW='\033[1;33m'
TEST_BLUE='\033[0;34m'
TEST_NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test runner function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "${TEST_BLUE}TEST:${TEST_NC} $test_name"
    
    if eval "$test_command"; then
        echo -e "${TEST_GREEN}  PASS${TEST_NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${TEST_RED}  FAIL${TEST_NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Create temporary jj repo for testing
setup_test_repo() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Initialize jj repo
    jj git init --colocate 2>/dev/null || git init
    
    # Configure git
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Add fake origin remote
    git remote add origin "https://github.com/test/repo.git"
    
    # Create initial commit
    echo "initial" > README.md
    jj describe -m "Initial commit" 2>/dev/null || true
}

# Cleanup test repo
cleanup_test_repo() {
    local test_dir="$1"
    cd /
    rm -rf "$test_dir"
}

# Mock gh command for testing
mock_gh() {
    cat << 'EOF'
#!/bin/bash
# Mock gh command for testing
case "$1" in
    pr)
        case "$2" in
            view)
                echo '{"number": 123, "url": "https://github.com/test/repo/pull/123"}'
                ;;
            create)
                echo "https://github.com/test/repo/pull/123"
                ;;
            merge)
                echo "Merged"
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    run)
        echo '[]'
        ;;
    *)
        exit 0
        ;;
esac
EOF
}

# Report test results
report_results() {
    echo ""
    echo "========================================"
    echo -e "${TEST_GREEN}Passed:${TEST_NC} $TESTS_PASSED"
    echo -e "${TEST_RED}Failed:${TEST_NC} $TESTS_FAILED"
    echo "========================================"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

export -f run_test setup_test_repo cleanup_test_repo report_results
export TEST_RED TEST_GREEN TEST_YELLOW TEST_BLUE TEST_NC
export TESTS_PASSED TESTS_FAILED
