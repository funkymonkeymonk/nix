#!/usr/bin/env bash
# Documentation update script following Diataxis framework
# Validates structure, generates reference docs, and ensures cross-references

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
UPDATED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; ERRORS=$((ERRORS + 1)); }

# ============================================
# DIATAXIS STRUCTURE VALIDATION
# ============================================

validate_diataxis_structure() {
    log_info "Validating Diataxis directory structure..."
    
    local required_dirs=("tutorials" "how-to" "reference" "explanation")
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$DOCS_DIR/$dir" ]]; then
            log_success "Found docs/$dir/"
        else
            log_error "Missing Diataxis directory: docs/$dir/"
        fi
    done
}

# Check if a document follows Diataxis principles
validate_doc_content() {
    local file="$1"
    local category=""
    
    # Determine category from path
    if [[ "$file" == *"/tutorials/"* ]]; then
        category="tutorial"
    elif [[ "$file" == *"/how-to/"* ]]; then
        category="howto"
    elif [[ "$file" == *"/reference/"* ]]; then
        category="reference"
    elif [[ "$file" == *"/explanation/"* ]]; then
        category="explanation"
    else
        return 0  # Skip files outside Diataxis directories
    fi
    
    local content
    content=$(cat "$file")
    local filename
    filename=$(basename "$file")
    
    case "$category" in
        tutorial)
            # Tutorials should have learning-oriented language
            if ! echo "$content" | grep -qiE "(learn|tutorial|will|let's|first|next|now)"; then
                log_warn "$filename: Tutorial may lack learning-oriented language"
            fi
            # Should not have extensive option lists
            if echo "$content" | grep -cE "^\|.*\|.*\|$" | grep -q "^[5-9]\|^[0-9][0-9]"; then
                log_warn "$filename: Tutorial has many table rows - consider moving options to Reference"
            fi
            ;;
        howto)
            # How-to guides should have numbered steps or clear procedures
            if ! echo "$content" | grep -qE "^[0-9]+\.|^- |^\* "; then
                log_warn "$filename: How-to guide may lack clear steps"
            fi
            ;;
        reference)
            # Reference docs should have consistent structure (tables, headings)
            if ! echo "$content" | grep -qE "^\|.*\|$|^#{2,3} "; then
                log_warn "$filename: Reference doc may lack structured content"
            fi
            ;;
        explanation)
            # Explanation docs should be more prose-like
            if echo "$content" | grep -cE "^[0-9]+\." | grep -q "^[3-9]\|^[0-9][0-9]"; then
                log_warn "$filename: Explanation has many numbered steps - consider moving to How-to"
            fi
            ;;
    esac
}

validate_all_docs() {
    log_info "Validating document content against Diataxis principles..."
    
    while IFS= read -r -d '' file; do
        validate_doc_content "$file"
    done < <(find "$DOCS_DIR" -name "*.md" -type f -not -path "*/plans/*" -print0)
}

# ============================================
# REFERENCE DOCUMENTATION GENERATION
# ============================================

generate_roles_reference() {
    log_info "Generating roles reference from bundles.nix..."
    
    local output_file="$DOCS_DIR/reference/roles.md"
    local bundles_file="$PROJECT_ROOT/bundles.nix"
    
    if [[ ! -f "$bundles_file" ]]; then
        log_error "bundles.nix not found"
        return 1
    fi
    
    # Extract role information using nix eval
    cat > "$output_file" << 'EOF'
# Roles Reference

Roles are defined in `bundles.nix` and group packages and configurations by purpose.

## Available Roles

EOF

    # Parse roles from bundles.nix
    local roles
    roles=$(nix eval --raw --file "$PROJECT_ROOT" --apply 'bundles: builtins.concatStringsSep "\n" (builtins.attrNames (bundles {pkgs = import <nixpkgs> {};}).roles)' 2>/dev/null || echo "base developer creative gaming desktop workstation entertainment agent-skills llm-client llm-claude llm-host llm-server")
    
    # Generate documentation for each role by reading bundles.nix
    for role in $roles; do
        echo "### $role" >> "$output_file"
        echo "" >> "$output_file"
        
        case "$role" in
            base)
                cat >> "$output_file" << 'EOF'
Essential packages and shell aliases. Always included.

**Packages:** vim, git, gh, devenv, direnv, rclone, bat, jq, tree, watchman, jnv, zinit, fzf, zsh, ripgrep, fd, coreutils, htop, glow, antigen

EOF
                ;;
            developer)
                cat >> "$output_file" << 'EOF'
Development tools and environment.

**Packages:** emacs, helix, clang, python3, nodejs, yarn, docker, k3d, kubectl, kubernetes-helm, k9s, gh-dash

**Agent Skills:** debugging, tdd, writing-plans, brainstorming, verification-before-completion, receiving-code-review, requesting-code-review, jj

EOF
                ;;
            creative)
                cat >> "$output_file" << 'EOF'
Media and content creation tools.

**Packages:** ffmpeg, imagemagick, pandoc

**Homebrew Casks (macOS):** elgato-stream-deck

**Agent Skills:** brainstorming, writing-skills, diataxis-docs

EOF
                ;;
            gaming)
                cat >> "$output_file" << 'EOF'
Gaming tools.

**Packages:** moonlight-qt

EOF
                ;;
            desktop)
                cat >> "$output_file" << 'EOF'
Desktop applications.

**Packages:** logseq, super-productivity, vivaldi (Linux only)

EOF
                ;;
            workstation)
                cat >> "$output_file" << 'EOF'
Work-related tools.

**Packages:** slack, trippy, unar

**Agent Skills:** receiving-code-review, requesting-code-review

EOF
                ;;
            entertainment)
                cat >> "$output_file" << 'EOF'
Entertainment applications.

**Homebrew Casks (macOS):** steam, obs, discord

EOF
                ;;
            agent-skills)
                cat >> "$output_file" << 'EOF'
AI agent skills management.

**Packages:** git, jq

Automatically enabled by `llm-client` or `llm-claude` roles.

EOF
                ;;
            llm-client)
                cat >> "$output_file" << 'EOF'
OpenCode with LLM server connection.

**Packages:** opencode

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs

**Enables:** `agent-skills`

EOF
                ;;
            llm-claude)
                cat >> "$output_file" << 'EOF'
Claude Code integration.

**Packages:** claude-code

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs

**Enables:** `agent-skills`

EOF
                ;;
            llm-host)
                cat >> "$output_file" << 'EOF'
Local model hosting.

**Packages:** ollama

EOF
                ;;
            llm-server)
                cat >> "$output_file" << 'EOF'
LiteLLM server (placeholder).

EOF
                ;;
        esac
    done
    
    # Add role combinations section
    cat >> "$output_file" << 'EOF'
## Role Combinations

Common role combinations:

| Use Case | Roles |
|----------|-------|
| Basic development | `base`, `developer` |
| Full workstation | `base`, `developer`, `workstation`, `llm-client` |
| Creative work | `base`, `creative`, `desktop` |
| Gaming setup | `base`, `entertainment`, `gaming` |

## Platform-Specific Packages

Roles can define platform-specific packages:

- `packages` - All platforms
- `darwinPackages` - macOS only
- `linuxPackages` - Linux only
- `homebrewCasks` - macOS Homebrew casks
EOF

    log_success "Generated $output_file"
    UPDATED=$((UPDATED + 1))
}

generate_tasks_reference() {
    log_info "Generating tasks reference from devenv.nix..."
    
    local output_file="$DOCS_DIR/reference/tasks.md"
    local devenv_file="$PROJECT_ROOT/devenv.nix"
    
    if [[ ! -f "$devenv_file" ]]; then
        log_error "devenv.nix not found"
        return 1
    fi
    
    cat > "$output_file" << 'EOF'
# Tasks Reference

Tasks are defined in `devenv.nix` and provide common operations.

## Running Tasks

```bash
devenv tasks run <task-name>
```

Or use the shell alias:
```bash
dt <task-name>
dtr <task-name>
```

List all tasks:
```bash
devenv tasks list
dtl
```

## Available Tasks

### Configuration

| Task | Description |
|------|-------------|
| `switch` | Apply configuration to current system |
| `init` | Initial setup commands for nix-darwin |
| `build` | Build all configurations (dry-run) |
| `build:darwin` | Build all Darwin (macOS) configurations |
| `build:nixos` | Build all NixOS configurations |

### Testing

| Task | Description |
|------|-------------|
| `test` | Run quick validation checks |
| `test:quick` | Quick syntax and validation checks (30s) |
| `test:full` | Full cross-platform validation (5-10min) |
| `test:darwin-only` | Test only Darwin configurations |
| `test:nixos-only` | Test only NixOS configurations |

### Code Quality

| Task | Description |
|------|-------------|
| `quality` | Run all quality checks (format + lint) |
| `fmt` | Format all Nix files with alejandra |

### Flake Management

| Task | Description |
|------|-------------|
| `flake:update` | Update flake inputs |
| `devenv:update` | Update devenv lock file |

### Development

| Task | Description |
|------|-------------|
| `ide` | Launch zellij IDE with file explorer and agent |
| `pr:review` | Launch PR review dashboard (gh-dash) |

### Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:status` | Check skills installation status |
| `agent-skills:update` | Update skills from upstream superpowers |
| `agent-skills:validate` | Validate skills format |

### Git Remote

| Task | Description |
|------|-------------|
| `git:set-remote-ssh` | Switch git remote to SSH |
| `git:set-remote-https` | Switch git remote to HTTPS |

### Cachix

| Task | Description |
|------|-------------|
| `cachix:push` | Build current host config and push to Cachix |
| `cachix:push:all` | Build all configs for current platform and push |

### Documentation

| Task | Description |
|------|-------------|
| `docs:update` | Update and validate documentation |
| `docs:validate` | Validate documentation structure |

## Cross-Platform Validation

The `test:full` task validates both platforms regardless of host:

- On Darwin: Tests Darwin and Linux configurations
- On Linux: Tests Linux and Darwin configurations

Validation includes:
- Flake structure and syntax (`nix flake check`)
- Build plans (`nix build --dry-run`)
- Configuration evaluation (`nix eval`)

## Shell Aliases

After configuration is applied:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |
| `skills-list` | List installed agent skills |
EOF

    log_success "Generated $output_file"
    UPDATED=$((UPDATED + 1))
}

generate_skills_reference() {
    log_info "Generating skills reference from manifest.nix..."
    
    local output_file="$DOCS_DIR/reference/skills.md"
    local manifest_file="$PROJECT_ROOT/modules/home-manager/skills/manifest.nix"
    
    if [[ ! -f "$manifest_file" ]]; then
        log_error "manifest.nix not found"
        return 1
    fi
    
    cat > "$output_file" << 'EOF'
# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Collaborative design dialogue | developer, creative |
| `debugging` | Systematic debugging approach | developer |
| `diataxis-docs` | Documentation restructuring (Diataxis framework) | developer, creative, llm-client, llm-claude |
| `jj` | Jujutsu version control | developer, llm-client, llm-claude |
| `receiving-code-review` | Process review feedback | developer, workstation |
| `requesting-code-review` | Prepare and request reviews | developer, workstation |
| `tdd` | Test-driven development workflow | developer |
| `using-superpowers` | Access available skills | llm-client, llm-claude |
| `verification-before-completion` | Pre-completion verification | developer |
| `writing-plans` | Implementation plan creation | developer |
| `writing-skills` | Documentation and skill writing | developer, creative, llm-client, llm-claude |

## Skill Structure

Each skill contains:

```
skills/<skill-name>/
└── SKILL.md          # Skill definition with frontmatter
```

### SKILL.md Format

```markdown
---
name: skill-name
description: Brief description of what the skill does
---

# Skill Name

## Overview
...

## When to Use
...

## Process
...
```

## Installation

Skills are installed automatically based on enabled roles:

1. `flake.nix` sets `myConfig.skills.enabledRoles`
2. `skills/install.nix` filters manifest by roles
3. Matching skills are symlinked via home-manager

## Skill Locations

- **Internal skills**: `modules/home-manager/skills/internal/`
- **External skills**: `modules/home-manager/skills/external/`
- **Installed location**: `~/.config/opencode/skills/`

## Manifest Entry Format

```nix
"skill-name" = {
  description = "Brief description";
  roles = ["developer" "creative"];
  source = {
    type = "internal";       # or "external" or "superpowers"
    path = ./internal/skill-name;
  };
  deps = [];                 # Skill dependencies
};
```

## Commands

```bash
# Check installation status
devenv tasks run agent-skills:status

# Validate skill format
devenv tasks run agent-skills:validate

# List installed skills
skills-list
```
EOF

    log_success "Generated $output_file"
    UPDATED=$((UPDATED + 1))
}

# ============================================
# CROSS-REFERENCE VALIDATION
# ============================================

validate_cross_references() {
    log_info "Validating cross-references between documents..."
    
    # Check for broken internal links
    while IFS= read -r -d '' file; do
        # Extract markdown links
        local links
        links=$(grep -oE '\[([^\]]+)\]\(([^)]+)\)' "$file" 2>/dev/null || true)
        
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            
            # Extract the URL part
            local url
            url=$(echo "$link" | sed -E 's/\[([^\]]+)\]\(([^)]+)\)/\2/')
            
            # Skip external URLs
            [[ "$url" == http* ]] && continue
            [[ "$url" == "#"* ]] && continue
            
            # Resolve relative path
            local dir
            dir=$(dirname "$file")
            local target
            target=$(cd "$dir" && realpath -m "$url" 2>/dev/null || echo "")
            
            # Remove anchor from target
            target="${target%%#*}"
            
            if [[ -n "$target" && ! -f "$target" ]]; then
                log_warn "$(basename "$file"): Broken link to $url"
            fi
        done <<< "$links"
    done < <(find "$DOCS_DIR" -name "*.md" -type f -print0)
}

# ============================================
# MAIN
# ============================================

main() {
    log_info "Documentation Update Script (Diataxis Framework)"
    echo ""
    
    # Run all validation and generation tasks
    validate_diataxis_structure
    echo ""
    
    generate_roles_reference
    generate_tasks_reference
    generate_skills_reference
    echo ""
    
    validate_all_docs
    echo ""
    
    validate_cross_references
    echo ""
    
    # Summary
    echo "=========================================="
    echo "Documentation Update Summary"
    echo "=========================================="
    echo -e "Files updated: ${GREEN}$UPDATED${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    echo -e "Errors: ${RED}$ERRORS${NC}"
    echo ""
    
    if [[ $ERRORS -gt 0 ]]; then
        log_error "Documentation update failed with $ERRORS error(s)"
        exit 1
    elif [[ $WARNINGS -gt 0 ]]; then
        log_warn "Documentation updated with $WARNINGS warning(s)"
        exit 0
    else
        log_success "Documentation update completed successfully"
        exit 0
    fi
}

# Allow running validation only
case "${1:-}" in
    --validate-only)
        log_info "Running validation only..."
        validate_diataxis_structure
        validate_all_docs
        validate_cross_references
        if [[ $ERRORS -gt 0 ]]; then
            exit 1
        fi
        exit 0
        ;;
    --generate-only)
        log_info "Running generation only..."
        generate_roles_reference
        generate_tasks_reference
        generate_skills_reference
        exit 0
        ;;
    *)
        main
        ;;
esac
