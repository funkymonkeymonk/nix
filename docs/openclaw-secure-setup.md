# OpenClaw Secure MicroVM - GitHub PR Workflow

This guide documents the secure OpenClaw installation using GitHub's permission model with mandatory PR reviews.

## 🎯 Security Model: GitHub PR Workflow

**Core Principle**: OpenClaw never modifies files directly. All changes flow through GitHub Pull Requests that require your review.

### Workflow
1. OpenClaw clones `funkymonkeymonk/nix` using a GitHub PAT (Personal Access Token)
2. OpenClaw creates a branch for changes
3. OpenClaw opens a **draft PR** with its proposed changes
4. You review the PR in GitHub (as `funkymonkeymonk`)
5. Only after your approval can changes be merged

## 🔒 Security Architecture

### 1. **No Direct File System Access**
- OpenClaw uses GitHub API for all operations
- Local filesystem is isolated and minimal
- Changes are atomic (committed via git/GitHub)

### 2. **Branch Protection (GitHub-side)**
```yaml
# Recommended .github/settings.yml or branch protection rules
branches:
  - name: main
    protection:
      required_pull_request_reviews:
        required_approving_review_count: 1
        require_code_owner_reviews: true
        dismissal_restrictions:
          users: [funkymonkeymonk]
      restrictions:
        users: [funkymonkeymonk]  # Only you can push directly
```

### 3. **MicroVM Isolation**
- Runs in separate KVM VM
- 4GB RAM, 2 CPU limits
- No access to host filesystem
- Ephemeral (no persistence for attackers)

### 4. **GitHub PAT Restrictions**
The GitHub PAT in the `openclaw` 1Password vault should have:
- **Repository access**: Only `funkymonkeymonk/nix`
- **Permissions**: 
  - Contents: read/write (for branches/PRs)
  - Pull requests: write
  - No admin access
  - No organization access
  - No delete_repo

## 📋 Prerequisites

### 1. Create the `openclaw` 1Password Vault

```bash
# In 1Password CLI
op vault create openclaw --description "Secrets for OpenClaw AI agent"
```

### 2. Create the GitHub PAT Secret

```bash
# Create GitHub PAT at: https://github.com/settings/tokens
# Permissions needed:
#   - repo (full control of private repositories)
#   - workflow (if updating GitHub Actions)

# Store in 1Password
op item create \
  --category password \
  --title "github-pat" \
  --vault openclaw \
  password="ghp_xxxxxxxxxxxxxxxxxxxx"
```

### 3. Create Gateway Token

```bash
# Generate a strong random token
GATEWAY_TOKEN=$(openssl rand -hex 32)

# Store in 1Password
op item create \
  --category password \
  --title "gateway-token" \
  --vault openclaw \
  password="$GATEWAY_TOKEN"
```

### 4. Create OpenCode Zen API Key

```bash
# Get from: https://opencode.ai/auth (sign in to OpenCode Zen)
# This provides access to curated models including free tiers (Big Pickle, MiniMax M2.5 Free)
# Store in 1Password
op item create \
  --category password \
  --title "opencode-zen-api-key" \
  --vault openclaw \
  password="oc-..."
```

**Note**: OpenCode Zen is a curated gateway of AI models tested for coding agents. Benefits:
- **Big Pickle**: Free model available
- **MiniMax M2.5 Free**: Another free option
- **Claude/GPT models**: Available at competitive rates
- **No lock-in**: Can use other providers alongside
- **Pay-as-you-go**: Credit-based system with auto-reload option

See [OpenCode Zen pricing](https://docs.opencode.ai/docs/zen) for full details.

## 🚀 Setup Instructions

### Step 1: Verify Secrets Exist

```bash
# Check all required secrets exist in the openclaw vault
op vault list
op item list --vault openclaw
# Should see: gateway-token, github-pat, opencode-zen-api-key
```

### Step 2: Build the MicroVM

```bash
cd /home/monkey/repos/nix

# Build the configuration
nix build .#microvm.nixosConfigurations.openclaw-secure.config.system.build.toplevel

# Or run directly for testing
nix run .#microvm.nixosConfigurations.openclaw-secure.config.microvm.runner
```

### Step 3: Configure GitHub Branch Protection

In your `funkymonkeymonk/nix` repo, enable branch protection:

1. Go to **Settings** → **Branches**
2. Add rule for `main` branch:
   - ✅ **Require a pull request before merging**
   - ✅ **Require approvals** (1 approval)
   - ✅ **Dismiss stale PR approvals when new commits are pushed**
   - ✅ **Require review from code owners** (if using CODEOWNERS)
   - ✅ **Require status checks to pass** (optional)
   - ✅ **Require conversation resolution before merging**
   - ✅ **Include administrators** (yes, apply to you too!)
   - ✅ **Restrict who can push to matching branches**
     - Add yourself (`funkymonkeymonk`)

3. Optional: Add CODEOWNERS file to repo:
```bash
# .github/CODEOWNERS
* @funkymonkeymonk
```

### Step 4: Create PAT Request Directory

Create a directory for PAT scope requests:

```bash
cd /path/to/your/local/nix/repo
mkdir -p .pat-requests
echo "# PAT Scope Request History

This directory contains PAT scope requests from OpenClaw.
Each request is a markdown file that is reviewed via PR before approval.
" > .pat-requests/README.md
git add .pat-requests
git commit -m "Add PAT request directory for OpenClaw"
git push
```

### Step 5: Set Up GitHub Actions for PAT Automation

Create the GitHub Actions workflow that automatically creates PATs when you merge scope requests:

```bash
# In your nix repo, create the workflow directory
mkdir -p .github/workflows

# Copy the workflow from the documentation
cp /path/to/nix/docs/openclaw-pat-pr-workflow.md .github/workflows/create-pat-on-merge.yml
```

**Required GitHub Secrets** (add in repo Settings → Secrets):

1. **ADMIN_PAT_CREATION_TOKEN**: Fine-grained PAT with `admin:org` scope (yours)
   - Create at: https://github.com/settings/personal-access-tokens/new
   - Scopes: `admin:org` (only needed to create other PATs)
   - Expiration: 7 days (short-lived!)
   - **Security**: This token can only create PATs, not access your repos

2. **OP_SERVICE_ACCOUNT_TOKEN**: 1Password service account token
   ```bash
   # Create service account in 1Password
   op service-account create openclaw-ci \
     --vault openclaw \
     --permissions write \
     --description "GitHub Actions for OpenClaw PAT rotation"
   
   # Copy the token and add to GitHub secrets
   ```

3. **OPENCLAW_WEBHOOK_SECRET**: Random secret for webhook verification
   ```bash
   openssl rand -hex 32
   ```

4. **OPENCLAW_WEBHOOK_URL**: Webhook endpoint (optional, for notifications)

See `docs/openclaw-pat-pr-workflow.md` for the complete workflow file.

### Step 6: Create OpenClaw GitHub Account

Create a dedicated GitHub account for OpenClaw:
1. Sign up at github.com with email `openclaw@yourdomain.com`
2. Generate PAT from this account
3. Add as collaborator to `funkymonkeymonk/nix` with **Triage** or **Write** access
4. Use this account's PAT in the `openclaw` vault

This provides:
- Clear audit trail (all OpenClaw actions attributed to distinct user)
- Easy permission revocation (disable the account if needed)
- No confusion with your primary account activity

## 📝 Usage

### Starting OpenClaw

```bash
# Build and run the microvm
nix run .#microvm.nixosConfigurations.openclaw-secure.config.microvm.runner

# OpenClaw will:
# 1. Load secrets from 1Password via opnix
# 2. Clone funkymonkeymonk/nix repo
# 3. Start the gateway service
# 4. Be ready to accept commands via Discord/Telegram
```

### Making Changes

1. **You message OpenClaw** (via Discord/Telegram):
   ```
   Can you update the README to document the new feature?
   ```

2. **OpenClaw**:
   - Creates a new branch: `openclaw/update-readme-2026-02-28`
   - Makes the changes locally in the VM
   - Commits with a descriptive message
   - Pushes to GitHub
   - Opens a **draft PR** with description of changes

3. **You review on GitHub**:
   - Go to https://github.com/funkymonkeymonk/nix/pulls
   - See the draft PR from OpenClaw
   - Review the diff
   - Request changes or mark ready for review
   - **Merge only when satisfied**

4. **OpenClaw monitors the PR**:
   - Can respond to review comments
   - Can push additional commits to address feedback
   - Waits for your approval

### Reviewing OpenClaw PRs

```bash
# List recent OpenClaw PRs
gh pr list --author openclaw --repo funkymonkeymonk/nix

# Check out and review locally
gh pr checkout 123
# Review the changes
git diff main...
# Approve if good
gh pr review 123 --approve --body "LGTM!"
```

## 🔑 PAT Scope Management via PR (Fully Automated)

This uses the **full automated GitHub Actions workflow** - when you merge a PAT scope request PR, the workflow automatically creates the PAT and stores it in 1Password.

**Full technical details**: See `docs/openclaw-pat-pr-workflow.md` for the complete workflow file and advanced configuration.

### How It Works (Full Automation)

When OpenClaw needs new GitHub permissions (scopes), the automated workflow is:

1. **OpenClaw creates a branch**: `openclaw/pat-request-<id>`
2. **OpenClaw creates request file**: `.pat-requests/<date>-<id>.md`
3. **OpenClaw opens a draft PR** with the scope request
4. **You review the PR** - check requested scopes and justification
5. **You approve and merge** the PR
6. **GitHub Actions automatically**:
   - Creates a fine-grained PAT with approved scopes
   - Stores it in 1Password `openclaw` vault
   - Updates the active `github-pat` item
   - Notifies OpenClaw via webhook
   - Comments on PR with confirmation
7. **OpenClaw picks up the new token** and uses it immediately

All of this happens automatically upon PR merge - no manual PAT creation needed!

### Example: OpenClaw Requests `issues:read` Scope

**Step 1: OpenClaw requests new scope**
```bash
# Inside the microvm (as openclaw user)
openclaw-request-pat \
  --scopes "issues:read" \
  --justification "Need to check if PR closes an existing issue before creating duplicate" \
  --expires 90
```

**Step 2: PR is created automatically**
```
[PAT Request] 2026-02-28-a1b2c3d4: issues:read

Requesting new PAT scopes for OpenClaw operations.

**Scopes**: issues:read
**Justification**: Need to check if PR closes an existing issue before creating duplicate
**Duration**: 90 days
**Expiration**: 2026-05-29

Upon merge, GitHub Actions will:
1. ✅ Create fine-grained PAT with these scopes
2. ✅ Store in 1Password vault: `openclaw`
3. ✅ Update `github-pat` item with new token
4. ✅ Notify OpenClaw of token rotation
5. ✅ Revoke previous token after 24h grace period
```

**Step 3: You review the request**
```bash
# Check the request file
cat .pat-requests/2026-02-28-a1b2c3d4.md

# Review checklist:
# ✅ Scope is minimal (issues:read, not issues:write or admin)
# ✅ Justification is legitimate and specific
# ✅ No dangerous scopes requested
# ✅ Expiration is reasonable (90 days)
# ✅ Request ID is unique and traceable
```

**Step 4: You approve and merge**

Just click "Merge" - the automation handles everything else!

**Step 5: Automation executes** (takes ~30 seconds)

GitHub Actions:
1. Parses the merged request file
2. Creates fine-grained PAT via GitHub API:
   ```json
   {
     "name": "openclaw-2026-02-28-a1b2c3d4",
     "target_repository_ids": [123456789],
     "permissions": {
       "contents": "write",
       "pull_requests": "write",
       "issues": "read",
       "metadata": "read"
     },
     "expires_at": "2026-05-29T00:00:00Z"
   }
   ```
3. Stores in 1Password via op CLI
4. Updates the active token reference
5. Sends webhook to OpenClaw gateway
6. Posts confirmation comment on PR

**Step 6: OpenClaw automatically picks up new token**
- Receives webhook notification
- Reloads configuration from 1Password
- Tests new scope (can now read issues!)
- Continues operation with new permissions

### Automation Benefits

- **Zero manual steps** after PR approval
- **Atomic rotation**: Old token → PR merge → New token → Old revoked
- **Audit trail**: Git history shows every scope change with justification
- **Time-bound**: Every PAT has expiration, forces periodic review
- **Minimal by default**: Scopes are whitelisted in workflow config
- **Instant recovery**: If something breaks, revert the PR to rollback permissions

### Current Scopes (Default)

```yaml
# Initial PAT scopes for OpenClaw
contents: write        # Push commits, create branches
pull_requests: write   # Create and update PRs
metadata: read         # Required for repo operations
```

### Common Additional Scope Requests

| Scope | Use Case | Risk Level |
|-------|----------|------------|
| `issues:read` | Reference issues in PRs | Low |
| `issues:write` | Create issues from code | Medium |
| `actions:read` | Check workflow status | Low |
| `actions:write` | Trigger workflows | Medium |
| `pages:write` | Deploy to GitHub Pages | Low |

## 🛡️ Security Controls Summary

| Control | Implementation |
|---------|---------------|
| **Change Authorization** | GitHub PR + required review from funkymonkeymonk |
| **Scope of Access** | Single repo only (funkymonkeymonk/nix) |
| **Authentication** | GitHub PAT (stored in 1Password openclaw vault) |
| **Isolation** | MicroVM with 4GB RAM, 2 CPUs, no host access |
| **Audit Trail** | All actions logged in GitHub (commits, PRs, reviews) |
| **Permission Limits** | PAT has repo-only access, no admin/org access |
| **Self-Modification** | Only through PRs to funkymonkeymonk/nix |
| **Emergency Stop** | Disable PAT in GitHub or 1Password |

## 🔍 Monitoring & Auditing

### GitHub Audit Log

Check what OpenClaw has done:
```bash
# View recent activity
gh api /repos/funkymonkeymonk/nix/events | jq '.[] | select(.actor.login == "openclaw")'

# View PR history
gh pr list --author openclaw --state all
```

### 1Password Audit

```bash
# View who accessed secrets
op item get github-pat --vault openclaw --format json | jq '.usage'
```

### VM Logs

```bash
# In the microvm
journalctl -u openclaw-gateway -f
journalctl -u openclaw-init -f
```

## 🚨 Emergency Procedures

### Suspend OpenClaw Immediately

```bash
# Option 1: Stop the VM
pkill -f openclaw-secure

# Option 2: Revoke GitHub access
# - Go to GitHub Settings → Applications → Authorized tokens
# - Revoke the PAT

# Option 3: Disable in 1Password
op item delete github-pat --vault openclaw

# Option 4: Block in GitHub repo
# - Repo Settings → Manage access
# - Remove openclaw user from collaborators
```

### Review All OpenClaw Activity

```bash
# List all OpenClaw commits
git log --author="OpenClaw" --all

# Check for any direct pushes (should be none!)
git log --author="OpenClaw" --all --oneline --graph

# Review all PRs
gh pr list --author openclaw --state all --limit 100
```

## 🔧 Advanced Configuration

### Adding More Repositories

If you want OpenClaw to access other repos:

1. **Update PAT permissions** in GitHub (add repos)
2. **Add new repo secrets** to 1Password:
```bash
op item create --category password --title "github-pat-secondary" --vault openclaw password="ghp_..."
```
3. **Modify the flake** to pass additional repos to OpenClaw config

### Custom Review Requirements

Update `.github/CODEOWNERS`:
```bash
# Different review requirements per directory
/docs/    @funkymonkeymonk
/modules/ @funkymonkeymonk
/secrets/ @funkymonkeymonk  # No OpenClaw access to secrets
```

### Status Checks

Require CI checks before OpenClaw PRs can merge:
```bash
# In GitHub branch protection settings
# Require status checks:
#   - nix flake check
#   - tests
#   - lint
```

## 📊 Comparison: PR Workflow vs Direct Access

| Feature | Direct Access (Dangerous) | GitHub PR Workflow (This Setup) |
|---------|--------------------------|--------------------------------|
| **Trust in OpenClaw** | High - can directly modify files | Low - all changes reviewed |
| **Recovery from mistakes** | Difficult - may corrupt repo | Easy - just close the PR |
| **Audit trail** | Manual git log review | Full GitHub PR history |
| **Permission granularity** | Coarse (all or nothing) | Fine (per-repo via PAT) |
| **Emergency stop** | Kill VM, check all files | Revoke PAT, close PRs |
| **Multi-user review** | Not possible | Built-in via GitHub |
| **Integration with CI** | Manual | Automatic via PR checks |

## 🎓 Best Practices

1. **Never approve OpenClaw PRs without reviewing**
2. **Require CI checks to pass** before merging
3. **Use draft PRs** so they don't notify until ready
4. **Rotate the GitHub PAT** monthly
5. **Review the 1Password audit log** weekly
6. **Keep the VM ephemeral** - rebuild regularly
7. **Use separate GitHub account** for clear audit trail

## 🔗 References

- [GitHub Branch Protection Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [OpenClaw Nix Mode](https://docs.openclaw.ai/install/nix)
- [opnix Documentation](https://github.com/brizzbuzz/opnix)

## ✅ Verification Checklist

Before trusting this setup:

### 1Password Setup
- [ ] `openclaw` vault exists in 1Password
- [ ] `github-pat` item exists with limited repo access
- [ ] `gateway-token` item exists
- [ ] `opencode-zen-api-key` item exists
- [ ] 1Password Service Account created for GitHub Actions

### GitHub Setup
- [ ] Branch protection enabled on `funkymonkeymonk/nix`
- [ ] Require 1 approval from `funkymonkeymonk`
- [ ] `.pat-requests/` directory exists in repo
- [ ] CODEOWNERS file created (optional)

### GitHub Actions Automation
- [ ] `.github/workflows/create-pat-on-merge.yml` exists
- [ ] `ADMIN_PAT_CREATION_TOKEN` secret added to repo
- [ ] `OP_SERVICE_ACCOUNT_TOKEN` secret added to repo
- [ ] `OPENCLAW_WEBHOOK_SECRET` secret added to repo
- [ ] Test PAT creation workflow with test PR

### OpenClaw Testing
- [ ] Test PR workflow with a simple code change
- [ ] Test PAT scope request workflow
- [ ] Verify OpenClaw cannot push directly to main
- [ ] Verify PAT is created automatically on merge
- [ ] Verify old PAT is revoked after grace period
- [ ] Document emergency stop procedures

### Security Verification
- [ ] OpenClaw uses dedicated GitHub account (not your main)
- [ ] OpenClaw is collaborator only on `funkymonkeymonk/nix`
- [ ] No admin/org scopes in any PAT
- [ ] All PATs have 90-day expiration
- [ ] PAT creation token has 7-day expiration
- [ ] MicroVM has no host filesystem access
- [ ] Firewall blocks all inbound connections
