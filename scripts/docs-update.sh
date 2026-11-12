#!/usr/bin/env bash
# Documentation update script following Diataxis framework
# Validates structure, generates reference docs, and ensures cross-references

set -euo pipefail

# Determine project root - try multiple methods for robustness
# Method 1: Use git to find repository root (works in most cases)
if git rev-parse --show-toplevel &>/dev/null; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
# Method 2: Calculate from script location
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Method 3: Use current working directory as fallback
else
    PROJECT_ROOT="$(pwd)"
fi

# Verify we found a valid project root with expected structure
if [[ ! -d "$PROJECT_ROOT/docs" ]]; then
    echo "Error: Cannot find valid project root (docs/ directory not found at $PROJECT_ROOT/docs)" >&2
    echo "Current directory: $(pwd)" >&2
    echo "Git root: $(git rev-parse --show-toplevel 2>/dev/null || echo 'N/A')" >&2
    exit 1
fi

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
    log_info "Generating roles reference from modules/roles/..."
    
    local output_file="$DOCS_DIR/reference/roles.md"
    local roles_dir="$PROJECT_ROOT/modules/roles"
    
    if [[ ! -d "$roles_dir" ]]; then
        log_error "modules/roles/ directory not found"
        return 1
    fi
    
    # Extract role names from module files (excluding default.nix)
    cat > "$output_file" << 'EOF'
# Roles Reference

Roles are defined as NixOS modules in `modules/roles/`. Each role is gated by `myConfig.roles.<name>.enable`.

## Available Roles

EOF

    # Get role names from filenames without maintaining a separate role list.
    local roles
    roles=$(find "$roles_dir" -maxdepth 1 -type f -name '*.nix' ! -name 'default.nix' -printf '%f\n' \
        | sed 's/\.nix$//' \
        | sort)

    if [[ -z "$roles" ]]; then
        log_error "No role modules found in modules/roles/"
        return 1
    fi
    
    # Generate documentation for each role from module filenames
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


EOF
                ;;
            creative)
                cat >> "$output_file" << 'EOF'
Media and content creation tools.

**Packages:** ffmpeg, imagemagick, pandoc

**Homebrew Casks (macOS):** elgato-stream-deck


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
Shell aliases for listing and updating the installed personal skills.

EOF
                ;;
            opencode)
                cat >> "$output_file" << 'EOF'
OpenCode AI assistant with rtk token optimization.

**Packages:** opencode, rtk



EOF
                ;;
            claude)
                cat >> "$output_file" << 'EOF'
Claude Code AI assistant with rtk token optimization.

**Packages:** claude-code, rtk



EOF
                ;;
            pi)
                cat >> "$output_file" << 'EOF'
Pi coding agent with rtk token optimization.

**Packages:** pi-coding-agent, rtk


**Enables:** `pi` config management

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
| Full workstation | `base`, `developer`, `workstation`, `opencode` |
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

## Task Conventions

Tasks follow a `namespace:action` naming convention:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `*:all` | **Aggregate** — runs all tasks in the namespace | `check:all`, `test:all` |
| `*:name` | **Leaf** — specific operation | `check:lint`, `test:eval` |

Run the aggregate when you want everything in a category. Run the leaf when you want a specific thing.

## Available Tasks

### Quality Checks

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `check:all` | Lint + unit tests + config eval | ~30s |
| `check:lint` | Formatting (alejandra), dead code (deadnix), static analysis (statix), YAML | ~10s |
| `check:unit` | nix-unit eval tests (fast, no builds) | ~5s |

### Testing

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `test:all` | Eval + build checks + module tests | 2–10min |
| `test:eval` | Evaluate all NixOS and Darwin configurations | ~10s |
| `test:build` | Build all flake check targets (single eval) | 2–10min |
| `test:sketchybar` | Sketchybar module tests | ~30s |
| `test:onepassword` | 1Password module tests | ~30s |

### Documentation

| Task | Description |
|------|-------------|
| `docs:all` | Update + validate + generate |
| `docs:update` | Update and validate documentation (Diataxis) |
| `docs:validate` | Validate documentation structure only |
| `docs:generate` | Generate reference documentation only |

### System

| Task | Description |
|------|-------------|
| `system:switch` | Apply configuration to current system (platform-aware) |
| `system:init` | Initial nix-darwin setup (macOS only) |

### Validation

| Task | Description |
|------|-------------|
| `validate:all` | Disko + install-script validation |
| `validate:disko` | Validate disko disk configurations |
| `validate:install-script` | Validate install-machine.sh syntax |


### LLM / Benchmarking

| Task | Description |
|------|-------------|
| `benchmark:all` | Run all benchmark suites |
| `benchmark:lm-eval-gsm8k` | lm-eval GSM8K against local oMLX |
| `benchmark:lm-eval-mini` | Quick lm-eval smoke benchmark |
| `benchmark:lm-eval-leaderboard` | HuggingFace Open LLM Leaderboard v2 |
| `benchmark:lighteval-gsm8k` | lighteval GSM8K |
| `benchmark:bfcl-smoke` | BFCL function-calling smoke test against local oMLX |
| `profile:llm` | Profile LLM inference performance |
| `smoke:llm-stack` | Smoke test oMLX + Bifrost |

### Maintenance

| Task | Description |
|------|-------------|
| `flake:update` | Update flake and devenv inputs, then refresh fixed-output dependency hashes |

## Dependency Graph

The `*:all` aggregates use devenv's `after` mechanism to run leaves in the correct order:

```
check:all
├── check:lint
└── check:unit
    └── test:eval

test:all
├── test:eval
├── test:build
├── test:sketchybar
└── test:onepassword
```

Dependencies are declared, not orchestrated via shell — devenv handles scheduling.

## Shell Aliases

After entering the devenv shell:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |
| `s` | `devenv tasks run system:switch` |
| `switch` | `devenv tasks run system:switch` |
EOF

    log_success "Generated $output_file"
    UPDATED=$((UPDATED + 1))
}

generate_skills_reference() {
    log_info "Generating skills reference from the pinned personal-skills input..."
    
    local output_file="$DOCS_DIR/reference/skills.md"
    local skills_root
    skills_root=$(cd "$PROJECT_ROOT" && nix eval --impure --raw --expr \
        'let flake = builtins.getFlake (toString ./.); in toString flake.inputs.personal-skills + "/skills"') || {
        log_error "Could not resolve the personal-skills flake input"
        return 1
    }
    if [[ ! -d "$skills_root" ]]; then
        log_error "Personal skills directory not found: $skills_root"
        return 1
    fi
    
    local skill_files
    skill_files=$(find "$skills_root" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | sort)
    if [[ -z "$skill_files" ]]; then
        log_error "No SKILL.md files found under $skills_root"
        return 1
    fi
    local skills
    skills=$(printf '%s\n' "$skill_files" | while IFS= read -r path; do basename "$(dirname "$path")"; done | sort)
    
    if [[ -z "$skills" ]]; then
        log_error "No SKILL.md files found under $skills_root"
        return 1
    fi
    
    # Generate header
    cat > "$output_file" << 'EOF'
# Skills Reference

Skills come from the pinned public `personal-skills` flake input and install to `~/.agents/skills/`.

## Available Skills

| Skill | Description |
|-------|-------------|
EOF

    # Read each skill's description from its source frontmatter.
    while IFS= read -r skill; do
        local description
        description=$(sed -n 's/^description:[[:space:]]*//p' "$skills_root/$skill/SKILL.md" | head -1)
        if [[ "$description" == \"*\" ]]; then
            description="${description:1:${#description}-2}"
        fi
        description=$(printf '%s' "$description" | sed 's/|/\\|/g')
        
        printf '| `%s` | %s |\n' "$skill" "${description:-See SKILL.md}" >> "$output_file"
    done <<< "$skills"
    
    # Add footer sections
    cat >> "$output_file" << 'EOF'

## Installation

When `developer`, `creative`, `workstation`, `opencode`, `claude`, or `pi` is
enabled, Home Manager links complete skill directories to `~/.agents/skills/`.
The flake lock file pins the source revision. Update it with:

```bash
nix flake update personal-skills
```

Run `find ~/.agents/skills -name SKILL.md -print` to list installed skills.
Add or edit skills in the source repository, update this input, and rebuild.
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
