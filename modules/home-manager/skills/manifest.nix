# Skill manifest - defines all available skills with metadata
# Skills are installed based on enabled roles in the bundle configuration
{
  # Internal skills - defined in this repository
  "writing-skills" = {
    description = "Use when creating new skills, editing existing skills, or verifying skills work before deployment in this repository";
    roles = ["creative" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/writing-skills;
    };
    deps = [];
  };

  "diataxis-docs" = {
    description = "Use when updating, rewriting, or auditing documentation to follow the Diataxis framework";
    roles = ["creative" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/diataxis-docs;
    };
    deps = [];
  };

  "nix-opnix-secrets" = {
    description = "Use when managing 1Password secrets via Nix on nix-darwin. Covers mkOpnixSecretsGeneric, programs.onepassword-secrets, activation script ordering, and runtime patching of config files";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-opnix-secrets;
    };
    deps = [];
  };

  "nix-adding-services" = {
    description = "Use when adding a new service to this Nix flake. Covers the full lifecycle: package from source (Node/Rust/Python), service module, options, secrets, home-manager config, tests, target wiring, and validation";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-adding-services;
    };
    deps = [];
  };

  "nix-darwin-launchd-debugging" = {
    description = "Use when debugging nix-darwin launchd services that fail to start, exit with non-zero, or don't reload on switch. Covers EX_CONFIG, $HOME expansion trap, daemon vs user.agent, and manual plist reloading";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-darwin-launchd-debugging;
    };
    deps = [];
  };

  "nix-hf-models" = {
    description = "Use when pre-downloading HuggingFace models into the Nix store for local inference. Covers hf download CLI, fixed-output derivations, hash computation, and CDN/auth issues";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-hf-models;
    };
    deps = [];
  };

  # External skills - fetched from other repositories
  # Example: Uncomment and modify when you want to add external skills
  # "spec-driven-workflow" = {
  #   description = "SRE workflow patterns from Liatrio Labs";
  #   roles = ["developer" "workstation"];
  #   source = {
  #     type = "external";
  #     url = "github:liatrio-labs/spec-driven-workflow//sre-workflow/SKILL.md";
  #   };
  #   deps = [];
  # };

  # Jujutsu (jj) version control skill
  # Based on @coreyja/jj from https://github.com/coreyja/dotfiles/tree/main/.claude/skills/jj
  "jj" = {
    description = "Use Jujutsu (jj) for version control. Treats pushed commits as immutable; every PR update adds a single new commit on top of the remote tip (no force pushes). Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, merge-based sync, stacked PRs, and workspaces for multi-project isolation";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./external/jj;
    };
    deps = [];
    # OpenCode slash commands bundled with this skill
    commands = {
      path = ./external/jj/commands;
      list = ["finish" "pr" "pr-merge" "push" "update" "sync" "stack" "workspace"];
    };
  };

  # Ralph Loop specification skills
  "ralph-specs" = {
    description = "Use when planning features for autonomous AI implementation, converting ideas into Ralph Loop PRDs, or breaking work into atomic user stories for unattended agent execution";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/ralph-specs;
    };
    deps = [];
  };

  "prd-review" = {
    description = "Use when reviewing a PRD before or during Ralph Loop execution, checking story completion status, or validating story structure and dependencies in a prd.json file";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/prd-review;
    };
    deps = [];
  };

  "refining-specs" = {
    description = "Use when a specification has open questions requiring research, technical decisions, or user input to resolve";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/refining-specs;
    };
    deps = [];
  };

  "yak-shaving" = {
    description = "Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/yak-shaving;
    };
    deps = ["jj"];
    autoLoad = true;
    commands = {
      path = ./internal/yak-shaving/commands;
      list = ["shave"];
    };
  };

  "iterating-nix-embedded-scripts" = {
    description = "Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/iterating-nix-embedded-scripts;
    };
    deps = [];
  };

  zellij = {
    description = "Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/zellij;
    };
    deps = [];
  };

  # Personal skills - managed in this repository
  "creating-user-manual" = {
    description = "Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/creating-user-manual;
    };
    deps = [];
  };

  "devenv" = {
    description = "Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/devenv;
    };
    deps = [];
  };

  "innersource-pr-haiku" = {
    description = "Use when given a GitHub PR link and asked to thank a contributor with a haiku and approve the PR";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/innersource-pr-haiku;
    };
    deps = [];
  };

  "open-url-new-window" = {
    description = "Use when the user asks to open a URL in a new browser window (not a new tab), or when opening documentation/references on macOS without disrupting their current browser session";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/open-url-new-window;
    };
    deps = [];
  };

  # Superpowers skills (obra/superpowers, pinned via the `superpowers` flake
  # input) — selectively adopted. Skipped: finishing-a-development-branch and
  # sharing-skills (git-worktree-specific, superseded by this repo's jj
  # skill), writing-skills and testing-skills-with-subagents (this repo has
  # its own writing-skills skill covering the same ground).
  "brainstorming" = {
    description = "Use when creating or developing, before writing code or implementation plans - refines rough ideas into fully-formed designs through collaborative questioning, alternative exploration, and incremental validation. Don't use during clear 'mechanical' processes";
    roles = ["creative" "opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "brainstorming";
    };
    deps = [];
  };

  "condition-based-waiting" = {
    description = "Use when tests have race conditions, timing dependencies, or inconsistent pass/fail behavior - replaces arbitrary timeouts with condition polling to wait for actual state changes, eliminating flaky tests from timing guesses";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "condition-based-waiting";
    };
    deps = [];
  };

  "defense-in-depth" = {
    description = "Use when invalid data causes failures deep in execution, requiring validation at multiple system layers - validates at every layer data passes through to make bugs structurally impossible";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "defense-in-depth";
    };
    deps = [];
  };

  "root-cause-tracing" = {
    description = "Use when errors occur deep in execution and you need to trace back to find the original trigger - systematically traces bugs backward through call stack, adding instrumentation when needed, to identify source of invalid data or incorrect behavior";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "root-cause-tracing";
    };
    deps = [];
  };

  "test-driven-development" = {
    description = "Use when implementing any feature or bugfix, before writing implementation code - write the test first, watch it fail, write minimal code to pass; ensures tests actually verify behavior by requiring failure first";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "test-driven-development";
    };
    deps = [];
  };

  "testing-anti-patterns" = {
    description = "Use when writing or changing tests, adding mocks, or tempted to add test-only methods to production code - prevents testing mock behavior, production pollution with test-only methods, and mocking without understanding dependencies";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "testing-anti-patterns";
    };
    deps = [];
  };

  "verification-before-completion" = {
    description = "Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "verification-before-completion";
    };
    deps = [];
  };

  "receiving-code-review" = {
    description = "Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "receiving-code-review";
    };
    deps = [];
  };

  "executing-plans" = {
    description = "Use when partner provides a complete implementation plan to execute in controlled batches with review checkpoints - loads plan, reviews critically, executes tasks in batches, reports for review between batches";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "executing-plans";
    };
    deps = [];
  };

  # Require pi-subagents (nicobailon/pi-subagents) for pi's subagent
  # dispatch tool — see myConfig.pi.npmPackages. opencode/claude have
  # native Task tool / @mention subagent support.
  "dispatching-parallel-agents" = {
    description = "Use when facing 3+ independent failures that can be investigated without shared state or dependencies - dispatches multiple agents to investigate and fix independent problems concurrently";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "dispatching-parallel-agents";
    };
    deps = [];
  };

  "subagent-driven-development" = {
    description = "Use when executing implementation plans with independent tasks in the current session - dispatches fresh subagent for each task with code review between tasks, enabling fast iteration with quality gates";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "superpowers";
      skillName = "subagent-driven-development";
    };
    deps = [];
  };

  # Forked as internal copies (not pure superpowers passthrough) because
  # they contained git-specific commands, patched to jj equivalents.
  "writing-plans" = {
    description = "Use when design is complete and you need detailed implementation tasks for engineers with zero codebase context - creates comprehensive implementation plans with exact file paths, complete code examples, and verification steps assuming engineer has minimal domain knowledge";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/writing-plans;
    };
    deps = [];
  };

  "requesting-code-review" = {
    description = "Use when completing tasks, implementing major features, or before merging to verify work meets requirements - dispatches a code-reviewer subagent to review implementation against plan or requirements before proceeding";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/requesting-code-review;
    };
    deps = [];
  };

  "systematic-debugging" = {
    description = "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes - four-phase framework (root cause investigation, pattern analysis, hypothesis testing, implementation) that prevents guess-and-check debugging";
    roles = ["opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/systematic-debugging;
    };
    deps = [];
  };
}
