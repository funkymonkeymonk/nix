#!/usr/bin/env bash
# OpenClaw Secure Bootstrap Script
# Performs all bootstrapping steps for OpenClaw setup

set -e

echo "=========================================="
echo "OpenClaw Secure Bootstrap"
echo "=========================================="
echo ""
echo "This will set up:"
echo "  1. 1Password 'openclaw' vault"
echo "  2. Required secrets in 1Password"
echo "  3. GitHub PAT request directory"
echo "  4. GitHub Actions workflow for PAT automation"
echo "  5. OpenClaw GitHub account setup instructions"
echo ""
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Bootstrap cancelled"
  exit 0
fi

# Step 1: Check prerequisites
echo ""
echo "Step 1: Checking prerequisites..."

if ! command -v op &> /dev/null; then
  echo "❌ 1Password CLI (op) not found"
  echo "   Install: https://1password.com/downloads/command-line/"
  exit 1
fi
echo "✅ 1Password CLI found"

if ! op account list &> /dev/null; then
  echo "❌ Not signed in to 1Password"
  echo "   Run: op signin"
  exit 1
fi
echo "✅ Signed in to 1Password"

if ! command -v gh &> /dev/null; then
  echo "❌ GitHub CLI (gh) not found"
  echo "   Install: https://cli.github.com/"
  exit 1
fi
echo "✅ GitHub CLI found"

if ! gh auth status &> /dev/null; then
  echo "❌ Not authenticated with GitHub CLI"
  echo "   Run: gh auth login"
  exit 1
fi
echo "✅ Authenticated with GitHub"

# Step 2: Create 1Password vault
echo ""
echo "Step 2: Creating 1Password vault 'openclaw'..."

if op vault list | grep -q "openclaw"; then
  echo "ℹ️  Vault 'openclaw' already exists"
else
  op vault create openclaw --description "Secrets for OpenClaw AI agent"
  echo "✅ Created vault 'openclaw'"
fi

# Step 3: Create secrets
echo ""
echo "Step 3: Setting up secrets..."

# Gateway token
if op item get gateway-token --vault openclaw &> /dev/null; then
  echo "ℹ️  gateway-token already exists"
else
  echo "Generating gateway token..."
  GATEWAY_TOKEN=$(openssl rand -hex 32)
  op item create \
    --category password \
    --title "gateway-token" \
    --vault openclaw \
    password="$GATEWAY_TOKEN"
  echo "✅ Created gateway-token"
fi

# GitHub PAT (placeholder - user needs to update)
if op item get github-pat --vault openclaw &> /dev/null; then
  echo "ℹ️  github-pat already exists"
else
  echo "Creating placeholder github-pat..."
  echo "⚠️  IMPORTANT: You must manually update this after creating the PAT!"
  op item create \
    --category password \
    --title "github-pat" \
    --vault openclaw \
    password="PLACEHOLDER_UPDATE_AFTER_CREATING_PAT"
  echo "   See docs/openclaw-secure-setup.md for PAT creation instructions"
  echo "✅ Created placeholder github-pat"
fi

# OpenCode Zen API key
if op item get opencode-zen-api-key --vault openclaw &> /dev/null; then
  echo "ℹ️  opencode-zen-api-key already exists"
else
  echo "Creating placeholder opencode-zen-api-key..."
  echo "⚠️  IMPORTANT: You must manually update this!"
  echo "   Get your key at: https://opencode.ai/auth"
  op item create \
    --category password \
    --title "opencode-zen-api-key" \
    --vault openclaw \
    password="PLACEHOLDER_GET_FROM_OPCODE_AI"
  echo "✅ Created placeholder opencode-zen-api-key"
fi

# Step 4: Create PAT request directory in repo
echo ""
echo "Step 4: Setting up GitHub repository structure..."

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Create .pat-requests directory
if [ -d ".pat-requests" ]; then
  echo "ℹ️  .pat-requests directory already exists"
else
  mkdir -p .pat-requests
  cat > .pat-requests/README.md << 'INNEREOF'
# PAT Scope Request History

This directory contains PAT (Personal Access Token) scope requests from OpenClaw.

Each request is a markdown file that gets reviewed via PR before approval.

## Format

Files named: `YYYY-MM-DD-<hash>.md`

## Process

1. OpenClaw creates a request file
2. OpenClaw opens a PR
3. You review the requested scopes
4. Upon merge, GitHub Actions creates the PAT
5. PAT is stored in 1Password

See docs/openclaw-secure-setup.md for full documentation.
INNEREOF
  git add .pat-requests
  echo "✅ Created .pat-requests directory"
fi

# Step 5: Create GitHub Actions workflow
echo ""
echo "Step 5: Creating GitHub Actions workflow..."

mkdir -p .github/workflows

if [ -f ".github/workflows/create-pat-on-merge.yml" ]; then
  echo "ℹ️  GitHub Actions workflow already exists"
else
  # Note: This is a simplified template - see docs/openclaw-pat-pr-workflow.md for full version
  cat > .github/workflows/create-pat-on-merge.yml << 'INNEREOF'
name: Create PAT on Scope Request Merge

on:
  push:
    branches:
      - main
    paths:
      - '.pat-requests/**'

jobs:
  create-pat:
    if: github.event.head_commit.message contains 'PAT Scope Request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Parse PAT Request
        id: parse
        run: |
          REQUEST_FILE=$(git diff --name-only HEAD~1 HEAD | grep '.pat-requests/' | head -1)
          echo "file=$REQUEST_FILE" >> "$GITHUB_OUTPUT"
          
          SCOPES=$(grep '^- ' "$REQUEST_FILE" | sed 's/^- //' | jq -R -s -c 'split("\\n") | map(select(length > 0))')
          echo "scopes=$SCOPES" >> "$GITHUB_OUTPUT"
          
          REQUEST_ID=$(grep 'Request ID' "$REQUEST_FILE" | sed 's/.*: //')
          echo "request_id=$REQUEST_ID" >> "$GITHUB_OUTPUT"

      - name: Install 1Password CLI
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          curl -sS https://downloads.1password.com/linux/keys/1password-archive-keyring.gpg | \
            sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
            sudo tee /etc/apt/sources.list.d/1password.list
          sudo apt update && sudo apt install 1password-cli

      - name: Create Fine-Grained PAT
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.ADMIN_PAT_CREATION_TOKEN }}
          script: |
            // See docs/openclaw-pat-pr-workflow.md for full implementation
            console.log('PAT creation workflow - configure secrets to enable');

      - name: Store in 1Password
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          echo "Storing PAT in 1Password..."

      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            console.log('PR comment with confirmation');
INNEREOF
  git add .github/workflows
  echo "✅ Created GitHub Actions workflow"
  echo "⚠️  IMPORTANT: You must add these GitHub secrets:"
  echo "   - ADMIN_PAT_CREATION_TOKEN (fine-grained PAT with admin:org scope)"
  echo "   - OP_SERVICE_ACCOUNT_TOKEN (1Password service account)"
  echo "   - OPENCLAW_WEBHOOK_SECRET (random secret)"
  echo "   - OPENCLAW_WEBHOOK_URL (optional webhook endpoint)"
fi

# Step 6: Instructions for GitHub account setup
echo ""
echo "Step 6: GitHub Account Setup Instructions"
echo "=========================================="
echo ""
echo "Create a dedicated OpenClaw GitHub account:"
echo ""
echo "1. Sign up at https://github.com with email like 'openclaw@yourdomain.com'"
echo "2. Go to https://github.com/funkymonkeymonk/nix/settings/access"
echo "3. Invite 'openclaw' as collaborator with 'Write' permission"
echo "4. Accept the invitation from the OpenClaw account"
echo "5. Create a fine-grained PAT from the OpenClaw account:"
echo "   - Go to https://github.com/settings/personal-access-tokens/new"
echo "   - Repository: funkymonkeymonk/nix ONLY"
echo "   - Permissions:"
echo "     - Contents: Read & Write"
echo "     - Pull requests: Read & Write"
echo "     - Metadata: Read (automatic)"
echo "   - Expiration: 90 days"
echo "6. Copy the PAT and update in 1Password:"
echo "   op item edit github-pat --vault openclaw password='github_pat_...'"
echo ""

# Step 7: Summary
echo ""
echo "=========================================="
echo "Bootstrap Complete!"
echo "=========================================="
echo ""
echo "✅ Completed:"
echo "   - 1Password vault 'openclaw' created"
echo "   - Secrets configured (with placeholders)"
echo "   - .pat-requests/ directory created"
echo "   - GitHub Actions workflow created"
echo ""
echo "⚠️  Manual steps required:"
echo "   1. Create OpenClaw GitHub account"
echo "   2. Add as collaborator to funkymonkeymonk/nix"
echo "   3. Create fine-grained PAT with minimal scopes"
echo "   4. Update github-pat secret in 1Password"
echo "   5. Update opencode-zen-api-key in 1Password"
echo "   6. Add GitHub secrets to repo for automation"
echo "   7. Enable branch protection on main"
echo "   8. Commit the new files: git add -A && git commit -m 'Add OpenClaw infrastructure'"
echo ""
echo "📚 Documentation:"
echo "   - docs/openclaw-secure-setup.md (setup guide)"
echo "   - docs/openclaw-pat-pr-workflow.md (automation details)"
echo ""
echo "🚀 Next step: Build and run OpenClaw"
echo "   nix run .#microvm.nixosConfigurations.openclaw-secure.config.microvm.runner"
echo ""
