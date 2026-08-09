# Skill manifest - defines all available skills with metadata
# Skills are installed based on enabled roles in the bundle configuration
let
  # Path to the writing-skills directory, which may be a plain directory
  # or a derivation that vendors upstream references (built at flake level).
  # Default: use local skill; overridden by flake.nix when inputs available.
  writingSkillsDir = ./internal/writing-skills;
in {
  # Internal skills - defined in this repository
  brainstorming = {
    description = "Help turn ideas into fully formed designs through collaborative dialogue";
    roles = ["developer" "creative"];
    source = {
      type = "internal";
      path = ./internal/brainstorming;
    };
    deps = [];
  };

  debugging = {
    description = "Systematic debugging approach for bugs, test failures, unexpected behavior";
    roles = ["developer"];
    source = {
      type = "internal";
      path = ./internal/debugging;
    };
    deps = [];
  };

  tdd = {
    description = "Test-driven development workflow for implementing features and bugfixes";
    roles = ["developer"];
    source = {
      type = "internal";
      path = ./internal/tdd;
    };
    deps = [];
  };

  openclaw = {
    description = "Guidelines for working with OpenClaw AI assistant configuration and deployment";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/openclaw;
    };
    deps = [];
  };

  "writing-plans" = {
    description = "Create detailed implementation plans from specs and requirements";
    roles = ["developer"];
    source = {
      type = "internal";
      path = ./internal/writing-plans;
    };
    deps = [];
  };

  "writing-skills" = {
    description = "Use when creating new skills, editing existing skills, or verifying skills work before deployment in this repository. Follows agentskills.io specification with vendored upstream references pinned by sha";
    roles = ["developer" "creative" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = writingSkillsDir;
    };
    deps = [];
  };

  "diataxis-docs" = {
    description = "Use when updating, rewriting, or auditing documentation to follow the Diataxis framework";
    roles = ["developer" "creative" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/diataxis-docs;
    };
    deps = [];
  };

  "verification-before-completion" = {
    description = "Run verification commands before claiming work is complete";
    roles = ["developer"];
    source = {
      type = "internal";
      path = ./internal/verification-before-completion;
    };
    deps = [];
  };

  "receiving-code-review" = {
    description = "Process code review feedback with technical rigor";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/receiving-code-review;
    };
    deps = [];
  };

  "requesting-code-review" = {
    description = "Properly request code reviews and prepare PRs";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/requesting-code-review;
    };
    deps = [];
  };

  "using-superpowers" = {
    description = "Access and use available skills for the current task";
    roles = ["opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/using-superpowers;
    };
    deps = [];
  };

  "nix-opnix-secrets" = {
    description = "Use when managing 1Password secrets via Nix on nix-darwin. Covers mkOpnixSecretsGeneric, programs.onepassword-secrets, activation script ordering, and runtime patching of config files";
    roles = ["developer" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-opnix-secrets;
    };
    deps = [];
  };

  "nix-adding-services" = {
    description = "Use when adding a new service to this Nix flake. Covers the full lifecycle: package from source (Node/Rust/Python), service module, options, secrets, home-manager config, tests, target wiring, and validation";
    roles = ["developer" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-adding-services;
    };
    deps = [];
  };

  "nix-darwin-launchd-debugging" = {
    description = "Use when debugging nix-darwin launchd services that fail to start, exit with non-zero, or don't reload on switch. Covers EX_CONFIG, $HOME expansion trap, daemon vs user.agent, and manual plist reloading";
    roles = ["developer" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/nix-darwin-launchd-debugging;
    };
    deps = [];
  };

  "nix-hf-models" = {
    description = "Use when pre-downloading HuggingFace models into the Nix store for local inference. Covers hf download CLI, fixed-output derivations, hash computation, and CDN/auth issues";
    roles = ["developer" "opencode" "claude" "pi"];
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
    roles = ["developer" "opencode" "claude"];
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
    description = "Write specifications optimized for Ralph Loop autonomous agent execution. Covers PRD structure, atomic user stories, and machine-verifiable acceptance criteria";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/ralph-specs;
    };
    deps = [];
  };

  "prd-review" = {
    description = "Display PRD files in human-readable format for review and status tracking. Shows progress, story details, and flags potential issues";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/prd-review;
    };
    deps = [];
  };

  "refining-specs" = {
    description = "Use when a specification has open questions requiring research, technical decisions, or user input to resolve";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/refining-specs;
    };
    deps = [];
  };

  "watch-ci-jobs" = {
    description = "Monitor GitHub Actions CI jobs with intelligent polling that adapts to historical run times";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/watch-ci-jobs;
    };
    deps = [];
  };

  "yak-shaving" = {
    description = "Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks";
    roles = ["developer" "opencode" "claude" "pi"];
    source = {
      type = "internal";
      path = ./internal/yak-shaving;
    };
    deps = ["jj" "watch-ci-jobs"];
    autoLoad = true;
    commands = {
      path = ./internal/yak-shaving/commands;
      list = ["shave"];
    };
  };

  "iterating-nix-embedded-scripts" = {
    description = "Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/iterating-nix-embedded-scripts;
    };
    deps = [];
  };

  zellij = {
    description = "Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/zellij;
    };
    deps = [];
  };

  # Personal skills - managed in this repository
  "creating-user-manual" = {
    description = "Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/creating-user-manual;
    };
    deps = [];
  };

  "devenv" = {
    description = "Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/devenv;
    };
    deps = [];
  };

  "infra-investigation" = {
    description = "Use when investigating errors, incidents, or performance issues that span Datadog logs/metrics, AWS infrastructure, Terraform/terrasaur config, and Kubernetes Helm values. Use when diagnosing root causes that require correlating multiple sources. Use when infrastructure facts need to be verified before being used in analysis";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/infra-investigation;
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
    description = "Open URLs in a new browser window using macOS native commands";
    roles = ["developer" "opencode" "claude"];
    source = {
      type = "internal";
      path = ./internal/open-url-new-window;
    };
    deps = [];
  };

  "vendor-technical-evaluation" = {
    description = "Use when evaluating third-party vendors for a Buy decision, driving or participating in a vendor technical evaluation, navigating the Draft/Review/Revision/Decision lifecycle, or handling escalations, score ties, author replacement, or failed security assessments";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/vendor-technical-evaluation;
    };
    deps = [];
  };

  "yak-jira-sync" = {
    description = "Use when creating Jira tickets from a yak backlog, syncing yaks to Jira, auditing whether open yaks have corresponding tickets, or ensuring a yak backlog and Jira board reflect the same work";
    roles = ["developer" "workstation"];
    source = {
      type = "internal";
      path = ./internal/yak-jira-sync;
    };
    deps = [];
  };
}
