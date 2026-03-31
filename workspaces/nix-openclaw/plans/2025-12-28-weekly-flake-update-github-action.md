# Weekly Flake Update GitHub Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a GitHub Action that runs weekly to update flake.lock and create PRs with automatic basic fixes and comprehensive reporting.

**Architecture:** Single YAML workflow file using GitHub Actions with bash script steps, leveraging existing Nix setup patterns from the current CI/CD pipeline.

**Tech Stack:** GitHub Actions, bash scripting, Nix flakes, GitHub CLI, jq for JSON processing

### Task 1: Create the workflow file structure

**Files:**
- Create: `.github/workflows/flake-update.yml`

**Step 1: Create basic workflow structure**

```yaml
---
name: Weekly Flake Update
on:
  schedule:
    # Every Friday at 4:00 AM UTC
    - cron: '0 4 * * 5'
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
  issues: write
concurrency:
  group: flake-update
  cancel-in-progress: false
jobs:
  flake-update:
    name: Update Flake and Create PR
    runs-on: ubuntu-latest
    defaults:
      run:
        shell: bash
```

**Step 2: Commit workflow structure**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add basic weekly flake update workflow structure"
```

### Task 2: Add Nix environment setup

**Files:**
- Modify: `.github/workflows/flake-update.yml`

**Step 1: Add Nix installation and cache setup**

Add these steps after the jobs section:

```yaml
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@v10
        with:
          extra-conf: |
            experimental-features = nix-command flakes
            sandbox = false
      
      - name: Magic Nix Cache
        uses: DeterminateSystems/magic-nix-cache-action@main
      
      - name: Install devenv.sh
        run: nix profile install --accept-flake-config nixpkgs#devenv
      
      - name: Install additional tools
        run: |
          nix profile install --accept-flake-config nixpkgs#jq
          nix profile install --accept-flake-config nixpkgs#gh
```

**Step 2: Commit Nix setup**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add Nix environment setup to flake update workflow"
```

### Task 3: Add PR discovery and management logic

**Files:**
- Modify: `.github/workflows/flake-update.yml`

**Step 1: Add PR discovery step**

Add this step after tool installation:

```yaml
      - name: Discover existing flake update PRs
        id: discover-prs
        run: |
          echo "Searching for existing flake update PRs..."
          existing_prs=$(gh pr list \
            --repo ${{ github.repository }} \
            --label "flake-update" \
            --state open \
            --json number,title \
            --jq '.[] | @base64')
          
          if [ -n "$existing_prs" ]; then
            echo "Found existing PRs"
            echo "existing_prs<<EOF" >> $GITHUB_OUTPUT
            echo "$existing_prs" >> $GITHUB_OUTPUT
            echo "EOF" >> $GITHUB_OUTPUT
          else
            echo "No existing PRs found"
          fi
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Step 2: Add old PR closure step**

Add this step after PR discovery:

```yaml
      - name: Close existing PRs after creating new one
        if: steps.discover-prs.outputs.existing_prs
        run: |
          # This will be populated later after new PR creation
          echo "Will close existing PRs after new PR is created"
          echo "existing_prs_to_close<<EOF" >> $GITHUB_ENV
          echo "${{ steps.discover-prs.outputs.existing_prs }}" >> $GITHUB_ENV
          echo "EOF" >> $GITHUB_ENV
```

**Step 3: Commit PR management logic**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add PR discovery and management logic"
```

### Task 4: Add flake update and fix logic

**Files:**
- Modify: `.github/workflows/flake-update.yml`

**Step 1: Add flake update step**

```yaml
      - name: Update flake.lock
        run: |
          echo "Updating flake.lock..."
          nix flake update --commit-lock-file --commit-lockfile-summary "chore: update flake.lock"
          
          if [ -n "$(git status --porcelain)" ]; then
            echo "Flake updated successfully"
            echo "flake_updated=true" >> $GITHUB_ENV
          else
            echo "No changes to flake.lock"
            echo "flake_updated=false" >> $GITHUB_ENV
          fi
```

**Step 2: Add basic fixes step**

```yaml
      - name: Attempt basic fixes for common breakage
        if: env.flake_updated == 'true'
        run: |
          echo "Attempting basic fixes for common issues..."
          
          # Create fix attempts log
          echo "fix_attempts_log<<EOF" >> $GITHUB_ENV
          echo "# Automated Fix Attempts" >> $GITHUB_ENV
          echo "" >> $GITHUB_ENV
          
          fixes_applied=0
          
          # Common package renames (can be expanded)
          declare -A package_renames=(
            ["ripgrep-all"]="ripgrepAll"
            # Add more renames as needed
          )
          
          for old_name in "${!package_renames[@]}"; do
            new_name="${package_renames[$old_name]}"
            if grep -r "packages\.${old_name}" . --include="*.nix" 2>/dev/null; then
              echo "Found potential rename: $old_name -> $new_name" >> $GITHUB_ENV
              sed -i.bak "s/packages\.${old_name}/packages\.${new_name}/g" $(find . -name "*.nix" -exec grep -l "packages\.${old_name}" {} \;)
              fixes_applied=$((fixes_applied + 1))
              echo "- Applied rename: $old_name -> $new_name" >> $GITHUB_ENV
            fi
          done
          
          if [ $fixes_applied -gt 0 ]; then
            echo "Applied $fixes_applied automated fixes"
            git add .
            git commit -m "fix: apply automated fixes for common package renames"
          else
            echo "No fixes applied" >> $GITHUB_ENV
          fi
          
          echo "" >> $GITHUB_ENV
          echo "EOF" >> $GITHUB_ENV
```

**Step 3: Commit update and fix logic**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add flake update and automated fix logic"
```

### Task 5: Add validation and reporting

**Files:**
- Modify: `.github/workflows/flake-update.yml`

**Step 1: Add validation step**

```yaml
      - name: Validate changes
        run: |
          echo "Validating updated flake..."
          
          # Run flake check
          if nix flake check --no-build; then
            echo "Flake validation passed"
            echo "validation_status=passed" >> $GITHUB_ENV
            echo "validation_result=✅ All validations passed" >> $GITHUB_ENV
          else
            echo "Flake validation failed"
            echo "validation_status=failed" >> $GITHUB_ENV
            echo "validation_result=❌ Validation failed - see logs" >> $GITHUB_ENV
          fi
          
          # Generate package changes summary
          echo "package_changes<<EOF" >> $GITHUB_ENV
          echo "## Package Changes" >> $GITHUB_ENV
          echo "" >> $GITHUB_ENV
          git log --oneline -1 >> $GITHUB_ENV
          echo "" >> $GITHUB_ENV
          echo "EOF" >> $GITHUB_ENV
```

**Step 2: Add PR creation step**

```yaml
      - name: Create Pull Request
        if: env.flake_updated == 'true'
        id: create-pr
        run: |
          branch_name="flake-update-$(date +%Y-%m-%d)"
          
          # Create and push branch
          git checkout -b "$branch_name"
          git push origin "$branch_name"
          
          # Generate PR description
          pr_description=$(cat << EOF
          # Weekly Flake Update - $(date +%Y-%m-%d)
          
          ## Status
          ${{ env.validation_result }}
          
          ## Executive Summary
          This PR contains the weekly automatic update of Nix flake dependencies.
          
          - **Status**: ${{ env.validation_status }}
          - **Automated fixes applied**: See below
          - **Validation**: Completed
          
          ${{ env.package_changes }}
          
          ${{ env.fix_attempts_log }}
          
          ## Technical Details
          
          ### Changes Applied
          - Updated flake.lock with latest package versions
          - Attempted automated fixes for common breakage patterns
          
          ### Test Results
          The full CI/CD pipeline will run on this PR to validate all changes.
          
          ### Next Steps
          1. Review the automated changes above
          2. Check CI/CD pipeline results
          3. Manually address any remaining build failures
          4. Merge if all tests pass
          
          ### Rollback Instructions
          If needed, revert to previous state:
          \`\`\`bash
          git checkout main
          git reset --hard HEAD~1
          \`\`\`
          
          ---
          
          🤖 This PR was created automatically by the weekly flake update workflow.
          EOF
          )
          
          # Create PR
          pr_url=$(gh pr create \
            --title "Weekly Flake Update - $(date +%Y-%m-%d)" \
            --body "$pr_description" \
            --label "flake-update" \
            --label "dependencies" \
            --repo ${{ github.repository }})
          
          echo "PR created: $pr_url"
          echo "pr_url=$pr_url" >> $GITHUB_OUTPUT
          echo "pr_number=$(echo $pr_url | sed 's/.*\/pull\/\([0-9]*\).*/\1/')" >> $GITHUB_OUTPUT
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Step 3: Commit validation and PR creation**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add validation and PR creation logic"
```

### Task 6: Add old PR closure and completion

**Files:**
- Modify: `.github/workflows/flake-update.yml`

**Step 1: Add old PR closure step**

```yaml
      - name: Close existing PRs
        if: steps.create-pr.outputs.pr_number && env.existing_prs_to_close
        run: |
          new_pr_number="${{ steps.create-pr.outputs.pr_number }}"
          new_pr_url="${{ steps.create-pr.outputs.pr_url }}"
          
          echo "$existing_prs_to_close" | while read -r pr_info; do
            if [ -n "$pr_info" ]; then
              pr_number=$(echo "$pr_info" | base64 -d | jq -r '.number')
              pr_title=$(echo "$pr_info" | base64 -d | jq -r '.title')
              
              echo "Closing PR #$pr_number: $pr_title"
              
              # Add comment before closing
              gh pr comment "$pr_number" \
                --body "🔄 Superseded by #$new_pr_number - This week's flake update is available at $new_pr_url" \
                --repo ${{ github.repository }}
              
              # Close PR
              gh pr close "$pr_number" \
                --comment "Superseded by #$new_pr_number" \
                --repo ${{ github.repository }}
              
              echo "Closed PR #$pr_number"
            fi
          done
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Step 2: Add workflow completion step**

```yaml
      - name: Workflow completion
        run: |
          if [ "${{ env.flake_updated }}" == "true" ]; then
            echo "✅ Flake update workflow completed successfully"
            echo "📄 PR: ${{ steps.create-pr.outputs.pr_url }}"
          else
            echo "ℹ️ No flake updates were needed"
          fi
```

**Step 3: Commit final workflow**

```bash
git add .github/workflows/flake-update.yml
git commit -m "feat: add old PR closure and workflow completion"
```

### Task 7: Add documentation and testing

**Files:**
- Modify: `README.md`

**Step 1: Update README with workflow information**

Find the "## 🤖 CI/CD Pipeline" section and add:

```markdown
### Weekly Flake Updates

- **Schedule**: Every Monday at 9:00 AM UTC
- **Function**: Updates flake.lock with latest package versions
- **Features**:
  - Automated basic fixes for common package renames
  - Comprehensive PR with technical details and summaries
  - Automatic cleanup of previous week's PR
  - Validation and reporting of all changes

The workflow creates PRs with the `flake-update` label and includes:
- Executive summary of changes
- Technical details of package updates
- List of automated fixes applied
- Validation results and next steps
```

**Step 2: Test workflow manually**

```bash
# Test workflow dispatch manually (after merging)
gh workflow run "Weekly Flake Update" --repo $(git config --get remote.origin.url | sed 's/.*://;s/\.git$//')
```

**Step 3: Commit documentation**

```bash
git add README.md
git commit -m "docs: document weekly flake update workflow"
```

### Task 8: Final validation and cleanup

**Files:**
- Validate: `.github/workflows/flake-update.yml`

**Step 1: Validate workflow syntax**

```bash
# Check YAML syntax
yamllint .github/workflows/flake-update.yml

# Test workflow structure
gh workflow view "Weekly Flake Update" --repo $(git config --get remote.origin.url | sed 's/.*://;s/\.git$//')
```

**Step 2: Final commit**

```bash
git add -A
git commit -m "feat: complete weekly flake update workflow implementation"
```

## Verification Steps

After implementation:

1. **Manual Workflow Test**:
   ```bash
   gh workflow run "Weekly Flake Update"
   ```

2. **Check PR Creation**:
   - Verify PR is created with correct labels and description
   - Check that technical details are included
   - Validate automated fixes are documented

3. **Test PR Lifecycle**:
   - Run workflow again
   - Verify old PR is closed with comment linking to new PR
   - Check that new PR supersedes old one properly

4. **Validate Fixes**:
   - Test with a flake that has known package renames
   - Verify fixes are attempted and logged
   - Check that failed fixes don't block PR creation

5. **Review Documentation**:
   - README is updated with workflow information
   - PR descriptions are comprehensive and clear
   - Error handling produces useful reports