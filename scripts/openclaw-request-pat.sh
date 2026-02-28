#!/usr/bin/env bash
# request-pat-scopes.sh - Script for OpenClaw to request new PAT scopes via PR
# This runs inside the microvm as the openclaw user

set -euo pipefail

# Configuration
REPO="funkymonkeymonk/nix"
REQUEST_DIR=".pat-requests"
DATE=$(date +%Y-%m-%d)
REQUEST_ID="${DATE}-$(openssl rand -hex 4)"

# Parse arguments
SCOPES=""
JUSTIFICATION=""
EXPIRATION_DAYS=90

while [[ $# -gt 0 ]]; do
  case $1 in
    --scopes)
      SCOPES="$2"
      shift 2
      ;;
    --justification)
      JUSTIFICATION="$2"
      shift 2
      ;;
    --expires)
      EXPIRATION_DAYS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$SCOPES" ] || [ -z "$JUSTIFICATION" ]; then
  echo "Usage: $0 --scopes 'scope1,scope2' --justification 'reason' [--expires 90]"
  exit 1
fi

cd ~/nix

# Create branch
BRANCH="openclaw/pat-request-${REQUEST_ID}"
git checkout -b "$BRANCH"

# Create request file
REQUEST_FILE="${REQUEST_DIR}/${REQUEST_ID}.md"
cat > "$REQUEST_FILE" << EOF
# PAT Scope Request: ${REQUEST_ID}

**Requested By**: @openclaw-agent
**Date**: ${DATE}
**Request ID**: ${REQUEST_ID}

## Scopes Requested

\`\`\`
${SCOPES}
\`\`\`

## Justification

${JUSTIFICATION}

## Duration
- **Expiration**: ${EXPIRATION_DAYS} days
- **Rotation reminder**: $(date -d "+${EXPIRATION_DAYS} days" +%Y-%m-%d)

## Security Review Checklist
- [ ] Scopes are minimal required for the use case
- [ ] No admin/org level scopes requested
- [ ] Reasonable expiration (not exceeding 90 days)
- [ ] Justification is clear and legitimate

## Approval Required
@funkymonkeymonk please review and approve

---
**Action on Merge**: GitHub Actions will create PAT and store in 1Password
EOF

# Commit and push
git add "$REQUEST_FILE"
git commit -m "PAT Scope Request: ${REQUEST_ID}

Scopes: ${SCOPES}

${JUSTIFICATION}"

git push origin "$BRANCH"

# Create PR using gh CLI
gh pr create \
  --repo "$REPO" \
  --title "[PAT Request] ${REQUEST_ID}: ${SCOPES}" \
  --body "Requesting new PAT scopes for OpenClaw operations.

**Scopes**: ${SCOPES}

**Justification**: ${JUSTIFICATION}

**Duration**: ${EXPIRATION_DAYS} days

Please review and approve. Upon merge, the GitHub Actions workflow will automatically create the PAT with these scopes and store it in 1Password.

/cc @funkymonkeymonk" \
  --draft

echo "✅ PAT scope request created: ${REQUEST_ID}"
echo "PR URL: $(gh pr view --json url -q .url)"
echo ""
echo "Waiting for your approval..."
