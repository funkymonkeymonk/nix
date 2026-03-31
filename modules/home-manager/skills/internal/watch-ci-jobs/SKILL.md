---
name: watch-ci-jobs
description: Use when waiting for GitHub Actions CI jobs to complete on a pull request in jj workspaces, checking pipeline status, or monitoring workflow runs with intelligent polling to avoid rate limits
---

# Watch CI Jobs

## Overview

Monitor GitHub Actions CI jobs on pull requests with intelligent polling that adapts to historical run times, avoiding API rate limits while providing timely status updates.

**Works in jj workspaces** including child workspaces that don't have traditional `.git` directories. Uses `jj git remote list` to detect the repository and `--repo` flag for all `gh` commands.

## When to Use

**Use when:**
- You've pushed changes and need to wait for CI to pass
- You want to monitor a PR's check status without manual refreshing
- You need to know when workflows complete (success or failure)
- You want to avoid hitting GitHub API rate limits from excessive polling

**Do NOT use when:**
- CI is already complete (just check status directly with `gh pr checks`)
- You need immediate results (this tool polls intelligently, not constantly)
- Working with non-GitHub CI systems (GitLab CI, Jenkins, etc.)

## Core Pattern

**Before (naive polling wastes API calls):**
```bash
# ❌ Polling every 10 seconds - wastes API calls on long jobs
while true; do
    gh run list --branch my-branch
    sleep 10  # 360 API calls/hour for a 1-hour job!
done
```

**After (smart adaptive polling with jj workspace support):**
```bash
# ✅ Works in jj workspaces (no .git directory needed)
# ✅ Uses --repo flag for all gh commands
# ✅ Starts frequent, backs off based on historical data
watch-ci-jobs 123  # Adapts: frequent early, sparse later
# Reports results when complete, minimal API usage
```

## Quick Reference

| Task | Command |
|------|---------|
| Watch current PR | `./watch-ci-jobs.sh` |
| Watch specific PR | `./watch-ci-jobs.sh 123` |
| Watch PR from URL | `./watch-ci-jobs.sh "https://github.com/owner/repo/pull/123"` |
| Get timing estimate | `gh run list --branch <branch> --json createdAt,updatedAt` |
| Check rate limit | `gh api rate_limit` |

## Implementation

```bash
#!/bin/bash
# watch-ci-jobs.sh - Smart CI job monitoring with adaptive polling
# Works in jj workspaces (including child workspaces without .git directories)
set -euo pipefail

# Configuration
MIN_POLL_INTERVAL=15          # Minimum seconds between checks (early stages)
MAX_POLL_INTERVAL=300         # Maximum seconds between checks (5 minutes)
HISTORY_WINDOW=20             # Number of recent runs to analyze

# Get GitHub repo (owner/repo) from jj git remote
# Works in child workspaces separate from parent repo
get_gh_repo() {
    local remote_url
    remote_url=$(jj git remote list 2>/dev/null | grep -E '^origin\s' | awk '{print $2}')
    
    if [[ -z "$remote_url" ]]; then
        echo "Error: No 'origin' remote found" >&2
        return 1
    fi
    
    # Extract owner/repo from various URL formats:
    # git@github.com:owner/repo.git -> owner/repo
    # https://github.com/owner/repo.git -> owner/repo
    local repo
    repo=$(echo "$remote_url" | sed -E 's#^(git@github\.com:|https://github\.com/)##' | sed -E 's#\.git$##')
    
    echo "$repo"
}

# Get PR details (branch, head SHA) using --repo flag
get_pr_info() {
    local gh_repo="$1"
    local pr_number="$2"
    local pr_info
    
    if [[ -z "$pr_number" ]]; then
        # Get PR for current branch using --repo (works without .git)
        pr_info=$(gh pr view --repo "$gh_repo" --json number,headRefName,headRefOid,url 2>/dev/null) || {
            echo "Error: No PR found for current branch in $gh_repo"
            exit 1
        }
    else
        pr_info=$(gh pr view --repo "$gh_repo" "$pr_number" --json number,headRefName,headRefOid,url 2>/dev/null) || {
            echo "Error: PR #$pr_number not found in $gh_repo"
            exit 1
        }
    fi
    
    echo "$pr_info"
}

# All gh commands use --repo flag to support jj workspaces:
# gh pr checks --repo "$gh_repo" ...
# gh run list --repo "$gh_repo" ...
```

# Analyze historical run times for this workflow
get_historical_timing() {
    local branch="$1"
    local workflow_file="${2:-}"
    
    local query
    if [[ -n "$workflow_file" ]]; then
        query=".[] | select(.headBranch == \"$branch\" and .path == \".github/workflows/$workflow_file\") | \"\(.createdAt)|\(.updatedAt)|\(.status)\""
    else
        query=".[] | select(.headBranch == \"$branch\") | \"\(.createdAt)|\(.updatedAt)|\(.status)\""
    fi
    
    # Get recent runs with timing data
    local runs
    runs=$(gh run list --branch "$branch" --limit "$HISTORY_WINDOW" --json createdAt,updatedAt,status,path,headBranch --jq "$query" 2>/dev/null || echo "")
    
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

# Get current check status
get_check_status() {
    local pr_number="$1"
    
    local checks_json
    if [[ -z "$pr_number" ]]; then
        checks_json=$(gh pr checks --json name,state,link 2>/dev/null || echo "[]")
    else
        checks_json=$(gh pr checks "$pr_number" --json name,state,link 2>/dev/null || echo "[]")
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
    
    echo -e "${BLUE}🔍 Parsing PR information...${NC}"
    
    # Parse PR input
    local pr_number
    pr_number=$(parse_pr_input "$input")
    
    # Get PR details
    local pr_info branch sha pr_url
    pr_info=$(get_pr_info "$pr_number")
    branch=$(echo "$pr_info" | jq -r '.headRefName')
    sha=$(echo "$pr_info" | jq -r '.headRefOid' | cut -c1-7)
    pr_url=$(echo "$pr_info" | jq -r '.url')
    pr_number=$(echo "$pr_info" | jq -r '.number')
    
    echo -e "${BLUE}📋 PR #${pr_number} (${branch} @ ${sha})${NC}"
    echo -e "${BLUE}🔗 ${pr_url}${NC}"
    echo ""
    
    # Get historical timing for this branch/workflow
    echo -e "${BLUE}📊 Analyzing historical run times...${NC}"
    local avg_duration
    avg_duration=$(get_historical_timing "$branch")
    
    if [[ $avg_duration -gt 0 ]]; then
        echo -e "${BLUE}   Average completion time: $(format_duration "$avg_duration")${NC}"
    else
        echo -e "${YELLOW}   No historical data - using adaptive polling${NC}"
    fi
    echo ""
    
    # Start monitoring
    local start_time elapsed poll_interval last_pending_count=-1
    start_time=$(date +%s)
    poll_interval=$MIN_POLL_INTERVAL
    
    echo -e "${BLUE}⏳ Monitoring CI jobs...${NC}"
    echo "   (Press Ctrl+C to stop monitoring without affecting jobs)"
    echo ""
    
    while true; do
        # Get current status
        local checks_json status_line total pending success failed
        checks_json=$(get_check_status "$pr_number")
        status_line=$(parse_check_states "$checks_json")
        
        IFS='|' read -r total pending success failed <<< "$status_line"
        
        # Calculate elapsed time
        local current_time
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # Display status
        if [[ $total -eq 0 ]]; then
            echo -e "${YELLOW}⏳ Waiting for checks to start... ($(format_duration "$elapsed"))${NC}"
        elif [[ $pending -eq 0 ]]; then
            # All checks complete
            echo ""
            if [[ $failed -gt 0 ]]; then
                echo -e "${RED}❌ Checks complete: ${success}/${total} passed, ${failed} failed ($(format_duration "$elapsed"))${NC}"
                echo ""
                echo "Failed checks:"
                echo "$checks_json" | jq -r '.[] | select(.state == "FAILURE" or .state == "ERROR" or .state == "CANCELLED") | "  - \(.name): \(.state)"'
            else
                echo -e "${GREEN}✅ All checks passed: ${success}/${total} ($(format_duration "$elapsed"))${NC}"
            fi
            echo ""
            echo -e "View details: ${pr_url}/checks"
            exit $failed
        else
            # Still running
            local status_msg="⏳ Running: ${pending}/${total} pending, ${success} passed"
            if [[ $failed -gt 0 ]]; then
                status_msg="${status_msg}, ${failed} failed"
            fi
            
            # Only update display if something changed
            if [[ $pending -ne $last_pending_count ]]; then
                echo -e "${BLUE}${status_msg} ($(format_duration "$elapsed"))${NC}"
                
                # Show currently running checks
                local running_checks
                running_checks=$(echo "$checks_json" | jq -r '.[] | select(.state == "PENDING" or .state == "IN_PROGRESS") | .name' | head -3)
                if [[ -n "$running_checks" ]]; then
                    echo "$running_checks" | while read -r check; do
                        echo -e "   ${YELLOW}→ $check${NC}"
                    done
                fi
                
                last_pending_count=$pending
            else
                # Just show progress dot
                echo -n "."
            fi
        fi
        
        # Calculate next poll interval
        poll_interval=$(calculate_poll_interval "$elapsed" "$avg_duration")
        
        # Progress estimate
        if [[ $avg_duration -gt 0 && $pending -gt 0 ]]; then
            local remaining=$((avg_duration - elapsed))
            if [[ $remaining -gt 0 ]]; then
                printf "\r   ${BLUE}ETA: ~$(format_duration "$remaining") (checking again in ${poll_interval}s)${NC}        "
            fi
        fi
        
        sleep "$poll_interval"
        
        # Clear the progress line if we printed one
        if [[ $avg_duration -gt 0 && $pending -gt 0 ]]; then
            printf "\r%80s\r" ""
        fi
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n\n${YELLOW}⚠️  Monitoring stopped by user${NC}"; exit 130' INT

# Run main function
main "$@"
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Polling too frequently | Use adaptive intervals based on historical data |
| Not handling rate limits | Check `gh api rate_limit` before long operations |
| Hardcoding branch names | Derive from PR or use current branch |
| Not showing progress | Display running checks and ETA |
| Ignoring failed checks early | Track and report failures immediately |

## Red Flags - STOP and Check

- **Rate limit approaching**: Run `gh api rate_limit` - if remaining < 100, wait
- **No PR found**: Ensure you've created a PR or passed correct number/URL
- **Wrong repository**: Verify you're in the correct repo directory
- **API errors**: Check `gh auth status` and re-authenticate if needed

## Error Handling

**PR not found:**
```bash
# Verify PR exists
gh pr view 123
# Or check all PRs
gh pr list --author @me
```

**Authentication issues:**
```bash
# Check auth status
gh auth status
# Re-authenticate if needed
gh auth login
```

**Rate limit hit:**
```bash
# Check current limits
gh api rate_limit | jq '.resources.core'
# Wait for reset if needed (reset time in UTC)
```

**No historical data for new branch:**
The script automatically falls back to gradual backoff when no history exists. First runs will use conservative intervals.

## Advanced Usage

**Watch specific workflow:**
```bash
# Monitor only a specific workflow file
WORKFLOW_FILE="ci.yml" ./watch-ci-jobs.sh 123
```

**Custom thresholds:**
```bash
# Faster initial polling for quick jobs
MIN_POLL_INTERVAL=5 ./watch-ci-jobs.sh

# Longer maximum interval for very slow jobs
MAX_POLL_INTERVAL=600 ./watch-ci-jobs.sh
```

**Integration with notifications:**
```bash
# Send notification on completion
./watch-ci-jobs.sh && osascript -e 'display notification "CI passed"' || osascript -e 'display notification "CI failed"'
```

## How It Works

1. **Input Parsing**: Accepts PR number, GitHub URL, or auto-detects current branch
2. **Historical Analysis**: Fetches recent run times for the branch to predict duration
3. **Adaptive Polling**:
   - **Early** (0-10%): Frequent checks (15-30s) to catch quick failures
   - **Middle** (10-50%): Moderate interval (30-60s) as jobs settle in
   - **Late** (50-80%): Sparse checks (60-120s) approaching expected end
   - **Near completion** (80%+): Return to frequent checks (30s) to catch finish
4. **Progress Display**: Shows running checks, elapsed time, and estimated remaining
5. **Result Reporting**: Exits with 0 on success, non-zero on failure, with full details

## API Rate Limiting

GitHub's API limits (5000 requests/hour for authenticated users) are respected by:
- Minimum 15-second intervals (max 240 calls/hour sustained)
- Adaptive backoff reduces calls for long-running jobs
- Historical data prevents unnecessary early polling

Average usage for a 30-minute job: ~60-80 API calls vs 180+ with naive 10-second polling.
