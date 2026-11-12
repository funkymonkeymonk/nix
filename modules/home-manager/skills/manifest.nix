# Optional agent-specific metadata for skills from the personal skills input.
# Skill content and directory membership come only from that pinned repository.
{
  "brainstorming" = {
    description = "Use when creating or developing, before writing code or implementation plans - refines rough ideas into fully-formed designs through collaborative questioning, alternative exploration, and incremental validation. Don't use during clear 'mechanical' processes";
    roles = ["creative" "opencode" "claude" "pi"];
  };

  "consumer-decision-guides" = {
    description = "Use when researching or writing consumer buying guides, product or service comparisons, best-of roundups, or Wirecutter-inspired recommendation articles - creates reader-first decision guides with transparent evidence, testing, tradeoffs, and clear picks.";
    roles = ["creative" "opencode" "claude" "pi"];
  };

  "creating-user-manual" = {
    description = "Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues";
    roles = ["opencode" "claude" "pi"];
  };

  "devenv" = {
    description = "Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues";
    roles = ["opencode" "claude" "pi"];
  };

  "diataxis-docs" = {
    description = "Use when updating, rewriting, or auditing documentation to follow the Diataxis framework";
    roles = ["creative" "opencode" "claude" "pi"];
  };

  "dispatching-parallel-agents" = {
    description = "Use when facing 3+ independent failures that can be investigated without shared state or dependencies - dispatches multiple agents to investigate and fix independent problems concurrently";
    roles = ["opencode" "claude" "pi"];
  };

  "executing-plans" = {
    description = "Use when partner provides a complete implementation plan to execute in controlled batches with review checkpoints - loads plan, reviews critically, executes tasks in batches, reports for review between batches";
    roles = ["opencode" "claude" "pi"];
  };

  "receiving-code-review" = {
    description = "Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation";
    roles = ["opencode" "claude" "pi"];
  };

  "requesting-code-review" = {
    description = "Use when completing tasks, implementing major features, or before merging to verify work meets requirements - dispatches a code-reviewer subagent to review implementation against plan or requirements before proceeding";
    roles = ["opencode" "claude" "pi"];
  };

  "subagent-driven-development" = {
    description = "Use when executing implementation plans with independent tasks in the current session - dispatches fresh subagent for each task with code review between tasks, enabling fast iteration with quality gates";
    roles = ["opencode" "claude" "pi"];
  };

  "systematic-debugging" = {
    description = "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes - four-phase framework (root cause investigation, pattern analysis, hypothesis testing, implementation) that prevents guess-and-check debugging";
    roles = ["opencode" "claude" "pi"];
  };

  "test-driven-development" = {
    description = "Use when implementing any feature or bugfix, before writing implementation code - write the test first, watch it fail, write minimal code to pass; ensures tests actually verify behavior by requiring failure first";
    roles = ["opencode" "claude" "pi"];
  };

  "verification-before-completion" = {
    description = "Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always";
    roles = ["opencode" "claude" "pi"];
  };

  "writing-plans" = {
    description = "Use when design is complete and you need detailed implementation tasks for engineers with zero codebase context - creates comprehensive implementation plans with exact file paths, complete code examples, and verification steps assuming engineer has minimal domain knowledge";
    roles = ["opencode" "claude" "pi"];
  };

  "writing-skills" = {
    description = "Use when creating new skills, editing existing skills, or verifying skills work before deployment in this repository";
    roles = ["creative" "opencode" "claude" "pi"];
  };
}
