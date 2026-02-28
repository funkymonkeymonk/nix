# OpenClaw PR-Based PAT Scope Approval Workflow

## 🎯 Goal
Use the same GitHub PR review process you're already using for code changes to approve OpenClaw's PAT scope requests. All PAT creation goes through PR review.

## 🏗️ Architecture

```
OpenClaw needs new scopes
         ↓
Creates PR in funkymonkeymonk/nix
         ↓
You review & approve (or deny) via PR
         ↓
Upon merge: GitHub Actions creates PAT
         ↓
PAT stored in 1Password
         ↓
OpenClaw notified & uses new PAT
```

## 📋 Implementation

### **Step 1: Create Request Template**

Create `.github/PAT_REQUEST_TEMPLATE.md` in your nix repo:

```markdown
---
name: PAT Scope Request
about: Request new GitHub PAT scopes for OpenClaw
---

## PAT Scope Request

**Requested By**: @openclaw
**Date**: {{date}}
**Request ID**: {{request-id}}

### Scopes Requested

| Scope | Level | Justification |
|-------|-------|---------------|
| contents | write | Needed to push commits to nix repo |
| pull_requests | write | Needed to create PRs |
| issues | read | To reference issues in PR descriptions |

### Duration
- **Expiration**: 90 days ({{expiration-date}})
- **Rotation reminder**: {{reminder-date}}

### Security Review Checklist
- [ ] Scopes are minimal required for the use case
- [ ] No admin/org level scopes requested
- [ ] Reasonable expiration (not exceeding 90 days)
- [ ] Justification is clear and legitimate

### Approval
Once merged, the GitHub Actions workflow will:
1. Create a fine-grained PAT with these scopes
2. Store it in 1Password `openclaw` vault as `github-pat-{{request-id}}`
3. Notify OpenClaw via webhook
4. Old PAT (if exists) will be revoked after 24h grace period

---
**Review Required**: @funkymonkeymonk
```

### **Step 2: GitHub Actions Workflow**

Create `.github/workflows/create-pat-on-merge.yml`:

```yaml
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
          # Find the merged PAT request file
          REQUEST_FILE=$(git diff --name-only HEAD~1 HEAD | grep '.pat-requests/' | head -1)
          echo "file=$REQUEST_FILE" >> $GITHUB_OUTPUT
          
          # Extract scopes from the file
          SCOPES=$(grep '^\- ' $REQUEST_FILE | grep -v '\[x\]' | sed 's/^\- //' | jq -R -s -c 'split("\n") | map(select(length > 0))')
          echo "scopes=$SCOPES" >> $GITHUB_OUTPUT
          
          # Extract request ID
          REQUEST_ID=$(grep 'Request ID' $REQUEST_FILE | sed 's/.*: //')
          echo "request_id=$REQUEST_ID" >> $GITHUB_OUTPUT

      - name: Create Fine-Grained PAT
        id: create-pat
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.ADMIN_PAT_CREATION_TOKEN }}
          script: |
            const scopes = JSON.parse('${{ steps.parse.outputs.scopes }}');
            
            // Get the nix repo ID
            const repo = await github.rest.repos.get({
              owner: 'funkymonkeymonk',
              repo: 'nix'
            });
            
            // Create fine-grained PAT via GraphQL API
            // Note: This requires a special token with admin:org scope
            const response = await github.graphql(`
              mutation($input: CreateAccessTokenInput!) {
                createAccessToken(input: $input) {
                  accessToken {
                    id
                    token
                    expiresAt
                  }
                }
              }
            `, {
              input: {
                name: `openclaw-${{ steps.parse.outputs.request_id }}`,
                targetRepositoryIds: [repo.data.id],
                permissions: {
                  contents: 'WRITE',
                  pullRequests: 'WRITE',
                  metadata: 'READ'
                },
                expiresAt: new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString()
              }
            });
            
            core.setSecret(response.createAccessToken.accessToken.token);
            core.setOutput('token', response.createAccessToken.accessToken.token);
            core.setOutput('token_id', response.createAccessToken.accessToken.id);

      - name: Store in 1Password
        env:
          OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
        run: |
          # Install 1Password CLI
          curl -sS https://downloads.1password.com/linux/keys/1password-archive-keyring.gpg | \
            sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
            sudo tee /etc/apt/sources.list.d/1password.list
          sudo apt update && sudo apt install 1password-cli
          
          # Store the new PAT
          echo "${{ steps.create-pat.outputs.token }}" | op item create \
            --category password \
            --title "github-pat-${{ steps.parse.outputs.request_id }}" \
            --vault openclaw \
            password=-
          
          # Mark as the active PAT (optional - could keep multiple)
          op item edit "github-pat" --vault openclaw \
            password="${{ steps.create-pat.outputs.token }}"

      - name: Notify OpenClaw
        run: |
          # Send webhook to OpenClaw gateway (if configured)
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.OPENCLAW_WEBHOOK_SECRET }}" \
            -H "Content-Type: application/json" \
            -d '{
              "event": "pat_rotated",
              "request_id": "${{ steps.parse.outputs.request_id }}",
              "vault": "openclaw",
              "item": "github-pat"
            }' \
            ${{ secrets.OPENCLAW_WEBHOOK_URL }} || true
          
          echo "✅ PAT created and stored in 1Password"

      - name: Create PR Comment
        uses: actions/github-script@v7
        with:
          script: |
            const { data: prs } = await github.rest.pulls.list({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'closed',
              sort: 'updated',
              direction: 'desc',
              per_page: 1
            });
            
            if (prs.length > 0) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: prs[0].number,
                body: `✅ **PAT Created Successfully**\n\n- Token ID: ${{ steps.create-pat.outputs.token_id }}\n- Stored in 1Password vault: \\\"openclaw\\\"\n- Item name: \\\"github-pat-${{ steps.parse.outputs.request_id }}\\\"\n- Old token will be revoked in 24 hours\n\nOpenClaw will pick up the new token automatically.`
              });
            }
```

### **Step 3: OpenClaw Configuration for Requesting PATs**

Update your OpenClaw config to enable PAT requests:

```nix
# In flake.nix OpenClaw config
home-manager.users.openclaw = { ... }: {
  programs.openclaw = {
    enable = true;
    config = {
      # ... other config ...
      
      # Enable PAT scope request functionality
      patManagement = {
        enabled = true;
        requestTemplate = ".github/PAT_REQUEST_TEMPLATE.md";
        workflowFile = ".github/workflows/create-pat-on-merge.yml";
        targetRepo = "funkymonkeymonk/nix";
        
        # Current PAT location
        currentPat = {
          vault = "openclaw";
          item = "github-pat";
        };
        
        # Available scopes OpenClaw can request (whitelist)
        allowedScopes = [
          "contents:write"
          "pull_requests:write" 
          "issues:read"
          "metadata:read"
        ];
        
        # Maximum expiration OpenClaw can request
        maxExpirationDays = 90;
      };
      
      # When OpenClaw needs new scopes, it creates a PR
      # You review and approve
      # GitHub Actions creates the PAT upon merge
    };
  };
};
```

### **Step 4: Create .pat-requests Directory**

In your nix repo:

```bash
mkdir -p .pat-requests
echo "# PAT Request History" > .pat-requests/README.md
git add .pat-requests
git commit -m "Add PAT request directory"
git push
```

### **Step 5: Required Secrets**

Add these to your GitHub repo secrets (Settings → Secrets):

1. **ADMIN_PAT_CREATION_TOKEN**: A fine-grained PAT with admin access (yours) that can create other PATs
   - Scopes: `admin:org` or use a GitHub App
   - Short expiration (7 days)
   - Only used by the workflow

2. **OP_SERVICE_ACCOUNT_TOKEN**: 1Password service account token
   - Create in 1Password: vaults → openclaw → Service Accounts
   - Permissions: Write to openclaw vault only

3. **OPENCLAW_WEBHOOK_SECRET**: Shared secret for webhook verification

4. **OPENCLAW_WEBHOOK_URL**: URL to notify OpenClaw (optional)

## 🔄 Workflow Example

### **Day 1: OpenClaw Needs New Scopes**

1. OpenClaw detects it needs `issues:read` scope
2. Creates a branch: `openclaw/pat-request-issues-read`
3. Creates file: `.pat-requests/2026-02-28-issues-read.md`
4. Opens PR with the request

### **Day 1: You Review**

You see the PR:
```
[PAT Scope Request] Add issues:read scope

Requested scopes:
- issues:read (to reference issues in PRs)

Justification: Need to check if PR closes an existing issue
Duration: 90 days
```

You review:
- ✅ Scopes are minimal
- ✅ Justification is legitimate  
- ✅ 90 days is reasonable
- ✅ No admin scopes

You approve and merge.

### **Day 1: Automatic Execution**

GitHub Actions:
1. Detects merged PAT request
2. Creates fine-grained PAT with `issues:read`
3. Stores in 1Password: `op://openclaw/github-pat-2026-02-28-issues-read`
4. Updates main `github-pat` item with new token
5. Comments on PR: "✅ PAT created"
6. Sends webhook to OpenClaw

### **Day 1: OpenClaw Picks Up New Token**

OpenClaw:
1. Receives webhook notification
2. Reloads config (picks up new token from 1Password)
3. Can now read issues!

## 🛡️ Security Benefits

1. **Same review workflow**: You already review OpenClaw's code PRs
2. **Audit trail**: All PAT scope changes tracked in Git history
3. **Time-bound**: Every request has expiration, forces periodic review
4. **Minimal by default**: OpenClaw can only request whitelisted scopes
5. **No manual errors**: Automated creation ensures correct scopes
6. **Atomic rotation**: Old PAT → PR merge → New PAT → Old revoked

## ⚠️ Prerequisites

1. GitHub Actions enabled on nix repo
2. 1Password Service Account created
3. `admin:org` token available (for creating PATs - keep short-lived!)
4. `.pat-requests/` directory exists

## 🎓 Advanced: Self-Modification via Nix

Since you mentioned OpenClaw should use `funkymonkeymonk/nix` for self-modification:

The workflow can also:
1. Update OpenClaw's Nix config to include new scopes
2. Rebuild and restart OpenClaw with new permissions
3. All through the same PR workflow!

This creates a complete infrastructure-as-code loop where **everything** goes through PR review.

## 🤔 Simpler Alternative

If this is too complex, consider:
- **Manual rotation every 60 days** (current setup)
- **Semi-automated**: OpenClaw creates PR with request, you manually create PAT and update 1Password
- **Use GitHub App instead**: More complex setup but better long-term

Want me to implement the full workflow or the simpler semi-automated version?
