# OpenCode Skills Management

This directory manages AI agent skills for OpenCode, Claude Code, and Pi agents. Skills are automatically deployed to `~/.config/opencode/skills/` during system activation.

## Directory Structure

```
skills/
├── README.md                 # This file
├── manifest.nix             # Central skill registry and metadata
├── install.nix              # External skill installation logic
├── internal/                # Skills defined in this repository
│   ├── brainstorming/       # Workflow for idea refinement
│   ├── debugging/           # Systematic debugging methodology
│   ├── tdd/                 # Test-driven development workflow
│   ├── creating-user-manual/# User manual / working-with-me document creation
│   ├── devenv/              # DevEnv developer environment configuration
│   ├── infra-investigation/ # Infrastructure troubleshooting across logs/metrics
│   ├── innersource-pr-haiku/# PR review with contributor haiku
│   ├── open-url-new-window/ # macOS URL opening commands
│   ├── shave-yaks/          # Yak backlog and task management
│   ├── vendor-technical-evaluation/ # Vendor evaluation workflows
│   ├── yak-jira-sync/       # Yak ↔ Jira synchronization
│   ├── ... (and many more)
│   └── zellij/              # Zellij terminal multiplexer
├── external/                # Skills fetched from external repositories
│   └── jj/                  # Jujutsu version control workflow
```

## How Skills Work

### 1. Skill Definition

Each skill is a directory containing:
- `SKILL.md` - Main skill document (required)
- Supporting docs like `basics.md`, `reference.md`, etc. (optional)
- Commands in `commands/` subdirectory (optional)
- Scripts or utilities (optional)

### 2. Skill Registration

All skills are registered in `manifest.nix`:

```nix
"skill-name" = {
  description = "Human-readable description";
  roles = ["developer" "opencode"];  # Who uses this skill
  source = {
    type = "internal";               # or "external" or "superpowers"
    path = ./internal/skill-name;    # Path for internal skills
  };
  deps = ["other-skill"];            # Optional dependencies
};
```

### 3. Role-Based Activation

Skills are deployed based on enabled roles:
- `developer` - Development workflows (TDD, debugging, testing)
- `opencode` - OpenCode agent-specific skills
- `claude` - Claude Code agent-specific skills
- `pi` - Pi agent-specific skills
- `workstation` - Work-focused skills

### 4. Deployment

During `system:switch`, home-manager reads the manifest and:
1. Filters skills matching enabled roles
2. Resolves skill paths (internal → filesystem, external → network fetch)
3. Installs to `~/.config/opencode/skills/<name>/`
4. Creates auto-load digest for skills marked `autoLoad = true`

## Adding a New Skill

### To Add an Internal Skill (Recommended for Project Work)

1. Create directory: `modules/home-manager/skills/internal/my-skill/`
2. Add skill file: `modules/home-manager/skills/internal/my-skill/SKILL.md`
3. Register in `manifest.nix`:

```nix
"my-skill" = {
  description = "What this skill does";
  roles = ["developer"];
  source = {
    type = "internal";
    path = ./internal/my-skill;
  };
  deps = [];
};
```

4. Commit and run `system:switch` to deploy
5. Test with: `cat ~/.config/opencode/skills/my-skill/SKILL.md`

### To Add an External Skill (From GitHub)

1. Register in `manifest.nix`:

```nix
"external-skill-name" = {
  description = "...";
  roles = ["developer"];
  source = {
    type = "external";
    url = "github:owner/repo//path/to/SKILL.md";
  };
  deps = [];
};
```

2. On next `system:switch`, it fetches via `npx skills add`

## Best Practices

### Prefer Internal Skills When:
- Skill is specific to this project/team
- You want tight feedback loops during development
- You're iterating on skill content
- You want it version-controlled with system config

### Use External Skills When:
- Skill is generic (benefits many projects/teams)
- Maintained upstream in a dedicated repo
- You want to share improvements with the community

### Organizing Skill Content

Each skill directory should be self-contained:

```
my-skill/
├── SKILL.md              # Main entry point (~100-500 lines)
├── workflows.md          # Detailed workflows (optional)
├── reference.md          # Quick lookup reference (optional)
├── commands/             # Bundled commands (optional)
│   └── my-command.md
└── scripts/              # Utility scripts (optional)
    └── helper.sh
```

## Testing Skills

1. **Verify deployment:**
   ```bash
   ls ~/.config/opencode/skills/my-skill/
   ```

2. **Check content:**
   ```bash
   cat ~/.config/opencode/skills/my-skill/SKILL.md | head -20
   ```

3. **Lint skill docs:**
   - Use `devenv tasks run check:lint` to validate Nix
   - Skills are Markdown; use standard Markdown linters

4. **Test in OpenCode:**
   - Skills are auto-discovered on next session
   - Use `/skills` command to list available skills
   - Or directly reference in prompts: "Load the my-skill and..."

## Troubleshooting

### Skills Not Deployed After `system:switch`

1. Verify `opencode.enable = true` in your host config (e.g., `hosts/wweaver/default.nix`)
2. Check enabled roles: `nix eval --impure ".#darwinConfigurations.wweaver.config.myConfig.skills.enabledRoles"`
3. Verify skill matches a role: check `manifest.nix` roles list
4. Test manually: `cat ~/.config/opencode/skills/my-skill/SKILL.md`

### External Skills Failing to Install

- Check 1Password secrets are configured
- Verify GitHub URL is correct and accessible
- Run: `npx skills@latest add <url> --global --yes --agent opencode`

### Path Resolution Errors

- Internal skills use `./internal/name` relative paths (resolved at evaluation time)
- Check paths exist before committing (`ls modules/home-manager/skills/internal/<name>/SKILL.md`)
- If error says "not tracked by Git", run: `git add modules/home-manager/skills/<name>/`

## See Also

- `manifest.nix` - Complete skill registry with all skills and metadata
- `install.nix` - Installation logic and activation scripts
- `lib.nix` - Helper functions for skill resolution and commands
- `/docs/reference/` - Project architecture and configuration
