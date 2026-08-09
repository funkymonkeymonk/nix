---
name: innersource-pr-haiku
description: Use when given a GitHub PR link and asked to thank a contributor with a haiku and approve the PR.
---

# Innersource PR Haiku

## Overview

Generate a witty, context-aware haiku that thanks an innersource contributor based on the actual content of their PR, then post it as a PR approval review comment.

## When to Use

- User provides a GitHub PR URL and wants to thank the contributor
- User asks to "approve" a PR with a haiku comment
- Celebrating innersource contributions

## Process

1. **Fetch PR details** using `gh pr view <PR_URL> --json title,body,additions,deletions,changedFiles,author,commits` to understand what the contributor actually did.

2. **Generate a witty haiku** (5-7-5 syllables) that:
   - References specific details from the PR (file types, feature name, what changed)
   - Thanks the contributor by name or handle if possible
   - Is witty, warm, and celebrates the innersource spirit
   - Avoids generic platitudes — make it specific to *this* PR

3. **Approve the PR with the haiku** as the review body:
   ```bash
   gh pr review <PR_URL> --approve --body "<haiku>"
   ```

## Haiku Style Guide

- **5-7-5 syllable structure** is non-negotiable
- Use concrete imagery from the PR (e.g., "your Go fix", "the React hook", "three failing tests")
- Wit > sentimentality — a clever pun beats a generic thank-you
- Reference the innersource act: forking, merging across team boundaries, strangers collaborating

## Example

For a PR fixing a race condition in a shared library:

```
Your mutex holds firm
A stranger's lock now our own
Main sleeps peacefully
```

## Common Mistakes

- **Too generic:** "Thank you for your work" — reference the actual change
- **Wrong syllables:** Count carefully; "contribution" = 5 syllables, trips people up
- **Forgetting approval:** Always use `--approve` flag, not just `--comment`
- **Using `gh pr comment`** instead of `gh pr review --approve` — the latter both approves AND comments
