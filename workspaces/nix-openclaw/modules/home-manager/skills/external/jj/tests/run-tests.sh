#!/usr/bin/env bash
# Test runner for jj workflow scripts
# Usage: ./run-tests.sh [test-file]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  JJ Workflow Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if specific test file provided
if [[ $# -eq 1 ]]; then
    TEST_FILE="$SCRIPT_DIR/$1"
    if [[ -f "$TEST_FILE" ]]; then
        echo -e "${BLUE}Running: $1${NC}"
        bash "$TEST_FILE"
        exit $?
    else
        echo -e "${RED}Test file not found: $1${NC}"
        exit 1
    fi
fi

# Run all tests
TOTAL_PASSED=0
TOTAL_FAILED=0

for test_file in "$SCRIPT_DIR"/*.bats; do
    if [[ -f "$test_file" ]]; then
        echo -e "${BLUE}Running: $(basename "$test_file")${NC}"
        if bash "$test_file"; then
            ((TOTAL_PASSED++))
        else
            ((TOTAL_FAILED++))
        fi
        echo ""
    fi
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Test files passed: $TOTAL_PASSED${NC}"
echo -e "${RED}Test files failed: $TOTAL_FAILED${NC}"

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
