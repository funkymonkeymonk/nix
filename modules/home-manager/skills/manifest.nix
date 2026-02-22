# Skill manifest - defines all available skills with metadata
# Skills are installed based on enabled roles in the bundle configuration
{
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
    description = "Use when creating new skills, editing existing skills, or verifying skills work before deployment";
    roles = ["developer" "creative" "llm-client" "llm-claude"];
    source = {
      type = "superpowers";
      skillName = "writing-skills";
    };
    deps = [];
  };

  "diataxis-docs" = {
    description = "Use when updating, rewriting, or auditing documentation to follow the Diataxis framework";
    roles = ["developer" "creative" "llm-client" "llm-claude"];
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
    roles = ["llm-client" "llm-claude"];
    source = {
      type = "internal";
      path = ./internal/using-superpowers;
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
    description = "Use Jujutsu (jj) for version control. Covers workflow, commits, bookmarks, pushing to GitHub, absorb, squash, stacked PRs, and workspaces for multi-project isolation";
    roles = ["developer" "llm-client" "llm-claude"];
    source = {
      type = "internal";
      path = ./external/jj;
    };
    deps = [];
  };

  # Ralph Loop specification skills
  "ralph-specs" = {
    description = "Write specifications optimized for Ralph Loop autonomous agent execution. Covers PRD structure, atomic user stories, and machine-verifiable acceptance criteria";
    roles = ["developer" "llm-client" "llm-claude"];
    source = {
      type = "internal";
      path = ./internal/ralph-specs;
    };
    deps = [];
  };

  "prd-review" = {
    description = "Display PRD files in human-readable format for review and status tracking. Shows progress, story details, and flags potential issues";
    roles = ["developer" "llm-client" "llm-claude"];
    source = {
      type = "internal";
      path = ./internal/prd-review;
    };
    deps = [];
  };
}
