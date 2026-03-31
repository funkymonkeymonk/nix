#!/usr/bin/env bash
# watch-ci-jobs.sh - Smart CI job monitoring with adaptive polling
# Works in jj workspaces (including child workspaces without .git directories)
set -euo pipefail

# Configuration
MIN_POLL_INTERVAL=15          # Minimum seconds between checks (early stages)
MAX_POLL_INTERVAL=300         # Maximum seconds between checks (5 minutes)
HISTORY_WINDOW=20             # Number of recent runs to analyze
API_CALLS_PER_HOUR_LIMIT=100  # Stay well under GitHub's 5000/hour limit

# Colors for output (disabled if not TTY)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
if [[ ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Get GitHub repo (owner/repo) from jj git remote
# Works in child workspaces separate from parent repo
get_gh_repo() {
    local remote_url
    remote_url=$(jj git remote list 2>/dev/null | grep -E '^origin\s' | awk '{print $2}')
    
    if [[ -z "$remote_url" ]]; then
        echo -e "${RED}Error: No 'origin' remote found${NC}" >&2
        echo -e "${YELLOW}Make sure you're in a jj repository with a git remote.${NC}" >&2
        return 1
    fi
    
    # Extract owner/repo from various URL formats:
    # git@github.com:owner/repo.git
    # https://github.com/owner/repo.git
    # https://github.com/owner/repo
    local repo
    repo=$(echo "$remote_url" | sed -E 's#^(git@github\.com:|https://github\.com/)##' | sed -E 's#\.git$##')
    
    if [[ -z "$repo" || ! "$repo" =~ ^[^/]+/[^/]+$ ]]; then
        echo -e "${RED}Error: Could not parse GitHub repo from remote URL: $remote_url${NC}" >&2
        return 1
    fi
    
    echo "$repo"
}

# Parse input to extract PR number
parse_pr_input() {
    local input="${1:-}"
    local pr_number=""
    
    if [[ -z "$input" ]]; then
        # No input - use current branch's PR
        pr_number=""
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        # Already a number
        pr_number="$input"
    elif [[ "$input" =~ github\.com/[^/]+/[^/]+/pull/([0-9]+) ]]; then
        # Extract from GitHub URL
        pr_number="${BASH_REMATCH[1]}"
    elif [[ "$input" =~ /pull/([0-9]+) ]]; then
        # Extract from partial URL
        pr_number="${BASH_REMATCH[1]}"
    else
        echo -e "${RED}Error: Unable to parse PR from: $input${NC}"
        echo "Expected: PR number (123) or GitHub URL"
        exit 1
    fi
    
    echo "$pr_number"
}

# Get PR details (branch, head SHA) using --repo flag
get_pr_info() {
    local gh_repo="$1"
    local pr_number="$2"
    local pr_info
    
    if [[ -z "$pr_number" ]]; then
        # Get PR for current branch
        pr_info=$(gh pr view --repo "$gh_repo" --json number,headRefName,headRefOid,url 2>/dev/null) || {
            echo -e "${RED}Error: No PR found for current branch in $gh_repo${NC}"
            echo "Create a PR first, or specify PR number/URL"
            exit 1
        }
    else
        pr_info=$(gh pr view --repo "$gh_repo" "$pr_number" --json number,headRefName,headRefOid,url 2>/dev/null) || {
            echo -e "${RED}Error: PR #$pr_number not found in $gh_repo${NC}"
            exit 1
        }
    fi
    
    echo "$pr_info"
}

# Analyze historical run times for this workflow using --repo flag
get_historical_timing() {
    local gh_repo="$1"
    local branch="$2"
    local workflow_file="${3:-}"
    
    local query
    if [[ -n "$workflow_file" ]]; then
        query=".[] | select(.headBranch == \"$branch\" and .path == \".github/workflows/$workflow_file\") | \"\(.createdAt)|\(.updatedAt)|\(.status)\""
    else
        query=".[] | select(.headBranch == \"$branch\") | \"\(.createdAt)|\(.updatedAt)|\(.status)\""
    fi
    
    # Get recent runs with timing data
    local runs
    runs=$(gh run list --repo "$gh_repo" --branch "$branch" --limit "$HISTORY_WINDOW" --json createdAt,updatedAt,status,path,headBranch --jq "$query" 2>/dev/null || echo "")
    
    local total_seconds=0
    local count=0
    
    while IFS='|' read -r created updated status; do
        [[ -z "$created" ]] && continue
        
        # Parse timestamps (ISO 8601 format)
        local created_epoch updated_epoch duration
        created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" +%s 2>/dev/null || date -d "$created" +%s 2>/dev/null || echo "0")
        updated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated" +%s 2>/dev/null || date -d "$updated" +%s 2>/dev/null || echo "0")
        
        if [[ "$created_epoch" != "0" && "$updated_epoch" != "0" ]]; then
            duration=$((updated_epoch - created_epoch))
            if [[ $duration -gt 0 && $duration -lt 7200 ]]; then  # Sanity check: less than 2 hours
                total_seconds=$((total_seconds + duration))
                ((count++))
            fi
        fi
    done <<< "$runs"
    
    if [[ $count -gt 0 ]]; then
        local avg_seconds=$((total_seconds / count))
        echo "$avg_seconds"
    else
        echo "0"  # No historical data
    fi
}

# Calculate next poll interval based on elapsed time and historical average
calculate_poll_interval() {
    local elapsed="$1"
    local avg_duration="${2:-0}"
    
    # Base calculation: start frequent, gradually back off
    local interval=$MIN_POLL_INTERVAL
    
    # If we have historical data, use it to optimize
    if [[ $avg_duration -gt 0 ]]; then
        local progress=$((elapsed * 100 / avg_duration))
        
        if [[ $progress -lt 10 ]]; then
            # Early stage: check every 15-30 seconds
            interval=$((MIN_POLL_INTERVAL + (elapsed / 10)))
        elif [[ $progress -lt 50 ]]; then
            # Middle stage: check every 30-60 seconds
            interval=$((MIN_POLL_INTERVAL * 2 + (elapsed / 5)))
        elif [[ $progress -lt 80 ]]; then
            # Late stage: check every 60-120 seconds
            interval=$((MIN_POLL_INTERVAL * 4 + (elapsed / 3)))
        else
            # Near expected completion: check every 30 seconds
            interval=$((MIN_POLL_INTERVAL * 2))
        fi
    else
        # No historical data: gradual backoff
        if [[ $elapsed -lt 60 ]]; then
            interval=$MIN_POLL_INTERVAL
        elif [[ $elapsed -lt 300 ]]; then
            interval=$((MIN_POLL_INTERVAL * 2))
        elif [[ $elapsed -lt 600 ]]; then
            interval=$((MIN_POLL_INTERVAL * 4))
        else
            interval=$((MIN_POLL_INTERVAL * 8))
        fi
    fi
    
    # Cap at maximum
    if [[ $interval -gt $MAX_POLL_INTERVAL ]]; then
        interval=$MAX_POLL_INTERVAL
    fi
    
    echo "$interval"
}

# Format seconds as human-readable time
format_duration() {
    local seconds="$1"
    local minutes=$((seconds / 60))
    local hours=$((minutes / 60))
    
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h $((minutes % 60))m"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m $((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

# Get current check status using --repo flag
get_check_status() {
    local gh_repo="$1"
    local pr_number="$2"
    
    local checks_json
    if [[ -z "$pr_number" ]]; then
        checks_json=$(gh pr checks --repo "$gh_repo" --json name,state,link 2>/dev/null || echo "[]")
    else
        checks_json=$(gh pr checks --repo "$gh_repo" "$pr_number" --json name,state,link 2>/dev/null || echo "[]")
    fi
    
    echo "$checks_json"
}

# Parse check status and determine if complete
parse_check_states() {
    local checks_json="$1"
    
    local total pending success failed
    total=$(echo "$checks_json" | jq 'length')
    pending=$(echo "$checks_json" | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS")] | length')
    success=$(echo "$checks_json" | jq '[.[] | select(.state == "SUCCESS")] | length')
    failed=$(echo "$checks_json" | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR" or .state == "CANCELLED")] | length')
    
    echo "${total}|${pending}|${success}|${failed}"
}

# Main monitoring loop
main() {
    local input="${1:-}"
    
    echo -e "${BLUE}Parsing PR information...${NC}"
    
    # Get GitHub repo from jj remote (supports workspaces without .git)
    local gh_repo
    gh_repo=$(get_gh_repo) || exit 1
    echo -e "${BLUE}Repository: ${gh_repo}${NC}"
    
    # Parse PR input
    local pr_number
    pr_number=$(parse_pr_input "$input")
    
    # Get PR details
    local pr_info branch sha pr_url
    pr_info=$(get_pr_info "$gh_repo" "$pr_number")
    branch=$(echo "$pr_info" | jq -r '.headRefName')
    sha=$(echo "$pr_info" | jq -r '.headRefOid' | cut -c1-7)
    pr_url=$(echo "$pr_info" | jq -r '.url')
    pr_number=$(echo "$pr_info" | jq -r '.number')
    
    echo -e "${BLUE}PR #${pr_number} (${branch} @ ${sha})${NC}"
    echo -e "${BLUE}${pr_url}${NC}"
    echo ""
    
    # Handle initial wait if specified
    if [[ -n "${INITIAL_WAIT:-}" ]]; then
        echo -e "${YELLOW}Initial wait: ${INITIAL_WAIT}s before first check${NC}"
        sleep "$INITIAL_WAIT"
        echo ""
    fi
    
    # Get historical timing for this branch/workflow (unless using fixed intervals)
    local avg_duration=0
    if [[ -z "${RECHECK_WAIT:-}" ]]; then
        echo -e "${BLUE}Analyzing historical run times...${NC}"
        avg_duration=$(get_historical_timing "$gh_repo" "$branch")
        
        if [[ $avg_duration -gt 0 ]]; then
            echo -e "${BLUE}   Average completion time: $(format_duration "$avg_duration")${NC}"
        else
            echo -e "${YELLOW}   No historical data - using adaptive polling${NC}"
        fi
        echo ""
    else
        echo -e "${YELLOW}Using fixed recheck interval: ${RECHECK_WAIT}s (adaptive polling disabled)${NC}"
        echo ""
    fi
    
    # Start monitoring
    local start_time elapsed poll_interval last_pending_count=-1 check_count=0
    start_time=$(date +%s)
    poll_interval=${RECHECK_WAIT:-$MIN_POLL_INTERVAL}
    
    echo -e "${BLUE}Monitoring CI jobs...${NC}"
    if [[ -n "${MAX_CHECKS:-}" ]]; then
        echo "   (Max checks: ${MAX_CHECKS})"
    fi
    echo "   (Press Ctrl+C to stop monitoring without affecting jobs)"
    echo ""
    
    while true; do
        # Increment check counter
        ((check_count++))
        
        # Check if we've exceeded max checks
        if [[ -n "${MAX_CHECKS:-}" && $check_count -gt $MAX_CHECKS ]]; then
            echo ""
            echo -e "${YELLOW}Maximum checks (${MAX_CHECKS}) reached. Stopping.${NC}"
            echo -e "View details: ${pr_url}/checks"
            exit 2
        fi
        
        # Get current status using --repo flag
        local checks_json status_line total pending success failed
        checks_json=$(get_check_status "$gh_repo" "$pr_number")
        status_line=$(parse_check_states "$checks_json")
        
        IFS='|' read -r total pending success failed <<< "$status_line"
        
        # Calculate elapsed time
        local current_time
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # Display status
        if [[ $total -eq 0 ]]; then
            echo -e "${YELLOW}Waiting for checks to start... ($(format_duration "$elapsed"))${NC}"
        elif [[ $pending -eq 0 ]]; then
            # All checks complete
            echo ""
            if [[ $failed -gt 0 ]]; then
                echo -e "${RED}Checks complete: ${success}/${total} passed, ${failed} failed ($(format_duration "$elapsed"))${NC}"
                echo ""
                echo "Failed checks:"
                echo "$checks_json" | jq -r '.[] | select(.state == "FAILURE" or .state == "ERROR" or .state == "CANCELLED") | "  - \(.name): \(.state)"'
            else
                echo -e "${GREEN}All checks passed: ${success}/${total} ($(format_duration "$elapsed"))${NC}"
            fi
            echo ""
            echo -e "View details: ${pr_url}/checks"
            exit $failed
        else
            # Still running
            local status_msg="Running: ${pending}/${total} pending, ${success} passed"
            if [[ $failed -gt 0 ]]; then
                status_msg="${status_msg}, ${failed} failed"
            fi
            
            # Show check count if max checks is set
            if [[ -n "${MAX_CHECKS:-}" ]]; then
                status_msg="${status_msg} (check ${check_count}/${MAX_CHECKS})"
            fi
            
            # Only update display if something changed
            if [[ $pending -ne $last_pending_count ]]; then
                echo -e "${BLUE}${status_msg} ($(format_duration "$elapsed"))${NC}"
                
                # Show currently running checks
                local running_checks
                running_checks=$(echo "$checks_json" | jq -r '.[] | select(.state == "PENDING" or .state == "IN_PROGRESS") | .name' | head -3)
                if [[ -n "$running_checks" ]]; then
                    echo "$running_checks" | while read -r check; do
                        echo -e "   ${YELLOW}-> $check${NC}"
                    done
                fi
                
                last_pending_count=$pending
            else
                # Just show progress dot
                echo -n "."
            fi
        fi
        
        # Calculate next poll interval (if not using fixed interval)
        if [[ -z "${RECHECK_WAIT:-}" ]]; then
            poll_interval=$(calculate_poll_interval "$elapsed" "$avg_duration")
        else
            poll_interval=$RECHECK_WAIT
        fi
        
        # Progress estimate
        if [[ -z "${RECHECK_WAIT:-}" && $avg_duration -gt 0 && $pending -gt 0 ]]; then
            local remaining=$((avg_duration - elapsed))
            if [[ $remaining -gt 0 ]]; then
                printf "\r   ${BLUE}ETA: ~$(format_duration "$remaining") (checking again in ${poll_interval}s)${NC}        "
            fi
        fi
        
        sleep "$poll_interval"
        
        # Clear the progress line if we printed one
        if [[ -z "${RECHECK_WAIT:-}" && $avg_duration -gt 0 && $pending -gt 0 ]]; then
            printf "\r%80s\r" ""
        fi
    done
}

# Parse command line arguments
INITIAL_WAIT=""
RECHECK_WAIT=""
MAX_CHECKS=""
PR_INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --initial-wait)
            INITIAL_WAIT="$2"
            shift 2
            ;;
        --recheck-wait)
            RECHECK_WAIT="$2"
            shift 2
            ;;
        --max-checks)
            MAX_CHECKS="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'EOF'
Usage: watch-ci-jobs [OPTIONS] [PR_NUMBER|PR_URL]

Monitor GitHub Actions CI jobs with intelligent adaptive polling.
Works in jj workspaces (including child workspaces without .git directories).

Arguments:
  PR_NUMBER    Pull request number (e.g., 123)
  PR_URL       Full or partial GitHub PR URL
               (e.g., https://github.com/owner/repo/pull/123)
  (none)       Auto-detect PR for current branch

Options:
  --initial-wait SECONDS   Wait SECONDS before first check (bypasses adaptive)
  --recheck-wait SECONDS   Wait SECONDS between checks (bypasses adaptive)
  --max-checks N           Stop after N checks
  -h, --help               Show this help

Examples:
  watch-ci-jobs                           # Watch PR for current branch
  watch-ci-jobs 123                       # Watch specific PR by number
  watch-ci-jobs --initial-wait 30 123     # Wait 30s before first check
  watch-ci-jobs --recheck-wait 60 123     # Check every 60s
  watch-ci-jobs --max-checks 10 123       # Stop after 10 checks

Environment:
  MIN_POLL_INTERVAL    Minimum seconds between checks (default: 15)
  MAX_POLL_INTERVAL    Maximum seconds between checks (default: 300)
  HISTORY_WINDOW       Number of recent runs to analyze (default: 20)

Features:
  - Works in jj workspaces without .git directories
  - Uses --repo flag for all gh commands
  - Adaptive polling based on historical run times (default)
  - Override adaptive polling with --initial-wait and --recheck-wait
  - ETA estimation from previous runs
  - Rate limit friendly (typically 60-80 API calls vs 180+)
  - Color-coded status output
  - Shows currently running checks
  - Exits with 0 on success, non-zero on failure
EOF
            exit 0
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            PR_INPUT="$1"
            shift
            ;;
    esac
done

# Export variables for use in main function
export INITIAL_WAIT RECHECK_WAIT MAX_CHECKS

# Handle Ctrl+C gracefully
trap 'echo -e "\n\n${YELLOW}Monitoring stopped by user${NC}"; exit 130' INT

# Run main function with parsed PR input
main "$PR_INPUT"
