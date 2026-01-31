#!/bin/bash
# create-pr-with-auto-squash.sh
set -euo pipefail

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="${1:-main}"
TITLE="${2:-$CURRENT_BRANCH}"
BODY="${3:-PR for $CURRENT_BRANCH}"

# 1. Check working tree is clean
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ Working tree is not clean. Commit or stash changes first."
    exit 1
fi

# 2. Push branch to origin (create upstream if needed)
echo "📤 Pushing branch $CURRENT_BRANCH to origin..."
git push -u origin "$CURRENT_BRANCH"

# 3. Check if PR already exists
if gh pr list --head "$CURRENT_BRANCH" --json number --jq 'length' | grep -q '^[1-9]'; then
    echo "⚠️  PR already exists for branch $CURRENT_BRANCH"
    echo "Existing PRs:"
    gh pr list --head "$CURRENT_BRANCH"
    exit 1
fi

# 4. Auto-detect base branch if not main
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
    echo "🔍 Auto-detected base branch: $BASE_BRANCH"
fi

# 5. Create PR with auto-squash merge
echo "🔄 Creating PR: $TITLE"
PR_URL=$(gh pr create \
    --base "$BASE_BRANCH" \
    --title "$TITLE" \
    --body "$BODY")

echo "✅ PR created: $PR_URL"

# 6. Configure auto-squash merge (does NOT merge immediately)
echo "⚙️  Configuring auto-squash merge..."
gh pr merge --squash --auto

echo "🎉 PR configured for auto-squash merge on completion!"