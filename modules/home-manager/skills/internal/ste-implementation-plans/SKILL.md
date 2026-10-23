---
name: ste-implementation-plans
description: Use when a user explicitly requests a software implementation plan in ASD-STE100 Simplified Technical English or practical STE-style prose.
---

# STE Implementation Plans

Create implementation plans that are clear to human engineers and coding agents. Use the target repository's conventions and the existing `writing-plans` structure when that skill is active. This skill adds ASD-STE100 Issue 9 language guidance and a linter review.

## Build a grounded plan

1. Identify the goal, scope, constraints, and completion conditions.
2. Inspect the target repository. Confirm file paths, tools, test commands, and existing terminology before naming them in the plan.
3. Separate known facts, assumptions, and open questions. Do not turn an unknown into a plan fact.
4. Order tasks by dependency. Each task must have a clear result that an engineer or coding agent can verify.
5. For each task, identify relevant files, the change to make, acceptance checks, and exact validation commands when the repository provides them.
6. Keep commands, identifiers, code, file names, and established technical terms exact. Do not invent replacement terms to satisfy a dictionary check.

Use the target repository's plan location and formatting conventions. If none exist, include the goal, scope, design summary, assumptions, ordered tasks, risks or open questions, and final verification.

## Write in practical STE

Use ASD-STE100 Issue 9 as a practical writing guide. Its controlled dictionary and rules apply to technical documentation. An implementation plan is not automatically a fully STE-controlled document.

- Prefer short, direct sentences and active voice. Use the imperative for task instructions.
- Give one action per task step. State conditions before the action when order matters.
- Keep task instructions close to the STE procedural limit of 20 words. Keep explanatory sentences close to the descriptive limit of 25 words when this does not remove necessary detail.
- Use vertical lists for sequences, requirements, and several related items.
- Use the same term for the same component or concept throughout the plan.
- Avoid contractions, semicolons, vague pronouns, idioms, unnecessary noun phrases, and long modifier chains.
- Use a dictionary-approved word only when its approved meaning fits. Preserve project-specific technical nouns, proper names, commands, and identifiers.
- Do not trade technical accuracy for a lower linter score. Explain or flag an exception when a term or construction must remain as written.

These practices reflect ASD-STE100 Issue 9, especially Rules 1.1–1.3, 1.8, 2.1, 3.6, 4.1, 4.3, 5.1–5.3, 6.3, 6.5, 8.1, and 9.4. They are guidance for plan prose, not a claim of full standard conformance.

## Lint the plan

The developer environment provides the open-source `ste` CLI. After drafting a Markdown plan, run:

```bash
ste lint --mode=flavored --format=agent --no-config path/to/plan.md
```

For an unsaved draft, send the plan text to `ste lint --mode=flavored --format=agent --no-config` on standard input. `--no-config` prevents a target repository's score threshold from turning this advisory review into a pass/fail gate.

Review every finding. Fix a finding when the edit improves clarity and preserves technical meaning. Keep exact technical terms, identifiers, quoted interface text, and commands when a replacement would be wrong. Treat the linter as an advisory check of machine-checkable rules, not as an STE certification or a substitute for human review. The flavored mode does not check words against the STE dictionary.

If a user requests a strict dictionary check, use `ste dict build --pdf <local-issue-9-pdf>` only when a local copy is available. The index belongs in the user's cache. Do not add the PDF or generated index to the repository. Review dictionary findings in context because STE permits technical nouns and technical verbs that are not in its dictionary.

If `ste` is unavailable, complete the manual review and state that the linter did not run. Do not install tools during plan generation.

## Final review

Before handing off the plan, confirm that:

- The task order follows dependencies.
- Each task identifies its files and observable completion checks.
- Validation commands are real and match the target repository.
- Terminology stays consistent, and unresolved assumptions remain visible.
- The `ste` findings were reviewed without weakening technical accuracy.

Never label a plan “STE-compliant.” State that it was reviewed with the `ste` linter in flavored mode when that check ran.
