---
title: "Skill Evaluation Prompt"
description: "Subagent prompt for evaluating agent skills against prompt engineering best practices"
type: reference
---

# Skill Evaluation Prompt

Run this prompt in a subagent to evaluate every installed agent skill.

## Sources

This evaluation rubric synthesizes best practices from:

- [Anthropic: Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Anthropic: Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
- [llmbestpractices: System Prompts](https://llmbestpractices.com/ai-agents/system-prompts)
- [llmbestpractices: System prompt design patterns](https://llmbestpractices.com/prompt-engineering/system-prompt-design-patterns)
- [llmbestpractices: Prompt templates](https://llmbestpractices.com/prompt-engineering/prompt-templates)
- [OpenAI: Prompt engineering best practices](https://developers.openai.com/api/docs/guides/prompting)
- [Claude Code: System Prompt Design Patterns](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/agent-development/references/system-prompt-design.md)
- [Context Engineering Patterns](https://contextpatterns.com/)
- [PEEM: Prompt Engineering Evaluation Metrics](https://arxiv.org/abs/2603.10477v1)

---

## Evaluation Prompt (send to subagent)

```
You are a prompt engineering evaluator specializing in agent system-prompt quality.

Your task: Read every SKILL.md file under ~/.pi/agent/skills/ and produce a
structured evaluation report. Use the rubric below.

## Evaluation Rubric

Score each skill on these 9 axes (1-5, where 5 = excellent). Provide a
one-sentence justification per axis.

### 1. CLARITY (Is the instruction unambiguous?)
- 5: Every instruction is specific and actionable. No vague language.
- 3: Some instructions are clear, but others require inference.
- 1: Heavy use of vague directives like "be helpful" or "do good work".

### 2. SPECIFICITY (Are constraints and output format defined?)
- 5: Output schema, length bounds, and format are pinned explicitly.
- 3: Output format is described in prose but not enforced.
- 1: No output contract at all; model must guess the shape.

### 3. CONTEXT EFFICIENCY (Does it respect the token budget?)
- 5: Hard information density. Every sentence carries a rule or example.
  No redundant examples, no restated constraints, no decorative prose.
- 3: Some fluff exists but the core signal is strong.
- 1: Kitchen-sink prompt. Repetitive examples, verbose explanations,
  restated rules. Could be 50% shorter without losing signal.

### 4. STRUCTURE (Is it organized for model attention?)
- 5: Follows a clear block structure (Identity → Capabilities → Constraints
  → Format → Examples). Uses XML tags or markdown headings consistently.
  Load-bearing rules are first AND restated at the end (recency bias).
- 3: Has headings but the order is ad-hoc. Mixed delimiter conventions.
- 1: Wall of text. No headings, no delimiters, no signal hierarchy.

### 5. ACTIONABILITY (Are steps concrete?)
- 5: Specific tool calls, file paths, command sequences, or decision trees.
  "Read X, then grep Y, then edit Z" rather than "analyze the code".
- 3: Some concrete steps mixed with vague guidance.
- 1: Entirely abstract: "think carefully", "use best judgment".

### 6. EDGE CASES (Does it handle failure modes?)
- 5: Lists explicit edge cases and what to do for each.
  (e.g. "If no issues found: provide positive feedback.")
- 3: Mentions some edge cases but not comprehensively.
- 1: No edge-case guidance. Agent will guess when things go wrong.

### 7. FEW-SHOT QUALITY (Are examples relevant and diverse?)
- 5: 3-5 examples covering happy path + edge cases + anti-patterns.
  Examples are wrapped in XML tags. No examples = N/A (score 3).
- 3: Few examples, or examples that are too similar to each other.
- 1: Examples contain errors, or are irrelevant to actual use.

### 8. VERSIONING & MAINTAINABILITY (Is it treated like code?)
- 5: Has a version tag, clear authorship, and a stated review date.
  Diff-friendly structure (headings, short paragraphs).
- 3: Has a name/description but no version or review metadata.
- 1: No metadata. Cannot tell when it was written or by whom.

### 9. REDUNDANCY (Is this skill duplicating another?)
- 5: Unique, non-overlapping scope. No other skill covers the same ground.
- 3: Partial overlap with one other skill; boundaries are muddy.
- 1: Near-complete duplication. Could be merged or deleted.

## Instructions

1. Read EVERY SKILL.md under ~/.pi/agent/skills/.
2. For each skill, score it on all 9 axes.
3. Compute a WEIGHTED SCORE:
   - Axes 1-6 (Clarity, Specificity, Context Efficiency, Structure,
     Actionability, Edge Cases) are CORE — weight 2x each.
   - Axes 7-9 (Few-shot, Versioning, Redundancy) are SUPPORT — weight 1x each.
   - Max raw score: 75. Normalize to 0-100 for readability.

4. Write a one-paragraph SUMMARY for each skill covering:
   - What it does (1 sentence)
   - Its strongest axis (why)
   - Its weakest axis (why)
   - The single biggest fix that would improve it

5. Write a KEEP / TRIM / REMOVE recommendation:
   - KEEP (score >= 70): High quality, unique value, low token cost or
     high signal-to-noise ratio.
   - TRIM (score 50-69): Core idea is good but bloated. Suggest specific
     cuts (line ranges or sections to delete).
   - REMOVE (score < 50): Low quality, high token cost, redundant with
     another skill, or the use case is too narrow to justify the tokens.

6. Write a GLOBAL SUMMARY table:
   | Skill | Score | Size (chars) | Size (tokens est.) | Rec |
   |-------|-------|--------------|-------------------|-----|
   ...
   Sort by score descending. Highlight the top 5 keepers and bottom 5
   candidates for removal.

7. Write a TOKEN BUDGET ANALYSIS:
   - Total tokens consumed by all skills
   - What % of a 32K context window this represents
   - What % of a 128K context window this represents
   - The 3 largest skills and whether they justify their size
   - A "lean" scenario: which skills to remove to get under 20K tokens

## Output Format

Produce your report in this exact structure:

```markdown
# Skill Evaluation Report
Generated: <date>
Evaluator: <model name>

## Global Summary
<the table from step 6>

## Token Budget Analysis
<analysis from step 7>

## Per-Skill Evaluation

### <skill-name>
**Score:** <normalized 0-100> (Raw: <raw>/75)
**Size:** <chars> chars (~<tokens> tokens)
**Recommendation:** KEEP | TRIM | REMOVE

| Axis | Score | Justification |
|------|-------|---------------|
| ... | ... | ... |

**What it does:** <1 sentence>
**Strongest:** <axis> — <why>
**Weakest:** <axis> — <why>
**Biggest fix:** <specific suggestion>

---
```

Repeat for every skill.

## End-of-prompt rule
Be ruthlessly honest. A bloated skill that "sounds nice" but wastes 10K
tokens on vague platitudes is worse than no skill at all. Score based on
signal-to-noise ratio, not politeness.
```

---

## How to Run

### Option 1: Single subagent (slower, thorough)

```bash
# Read this prompt into a variable and send to a subagent
cat docs/reference/skill-evaluation-prompt.md | pi subagent --agent prompt-evaluator
```

### Option 2: Parallel subagents (faster, per-skill)

Break the skill list into batches of 5-8 and run parallel evaluators,
then merge the reports.

### Option 3: Local run (no subagent)

Feed the prompt above directly to your LLM client with the skill files
as attachments/context.

---

## Post-Evaluation Actions

After receiving the report:

1. **Review TRIM recommendations** — apply the suggested cuts directly
   to the SKILL.md files.
2. **Review REMOVE recommendations** — remove the skill from the manifest
   (`modules/home-manager/skills/manifest.nix`) or disable its roles.
3. **Re-measure** — re-run the token count after edits to confirm savings.
4. **Re-evaluate** — run this prompt again after trimming to see scores improve.

See [Skills Reference](skills.md) for manifest format and role mapping.
