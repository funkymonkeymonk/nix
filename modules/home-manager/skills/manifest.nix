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
    description = "Writing skills for documentation, skill files, and technical content";
    roles = ["developer" "creative"];
    source = {
      type = "internal";
      path = ./internal/writing-skills;
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
}
