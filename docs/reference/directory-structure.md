# Directory Structure Reference

```
.
├── .github/                        # GitHub Actions workflows
│   └── workflows/
│       ├── ci.yml                  # CI/CD pipeline
│       └── flake-update.yml        # Weekly flake updates
│
├── modules/                        # Reusable Nix configurations
│   ├── common/                     # Shared configurations
│   │   ├── options.nix             # Type-safe configuration options
│   │   ├── users.nix               # User configuration
│   │   ├── shell.nix               # Shell configuration
│   │   └── onepassword.nix         # 1Password integration
│   │
│   ├── home-manager/               # User environment modules
│   │   ├── default.nix             # Module entry point
│   │   └── skills/                 # Agent skills management
│   │       ├── install.nix         # Skills installation module
│   │       ├── manifest.nix        # Skill definitions and roles
│   │       ├── internal/           # Skills defined in this repo
│   │       └── external/           # Skills from external sources
│   │
│   └── nixos/                      # Linux-specific modules
│       └── hardware.nix            # Hardware configuration
│
├── targets/                        # Machine-specific configurations
│   ├── core/                       # Minimal bootstrap configuration
│   ├── wweaver/                    # User-specific target
│   └── <machine>/                  # Per-machine targets
│
├── os/                             # Platform OS configurations
│   ├── darwin.nix                  # macOS configuration
│   └── nixos.nix                   # NixOS configuration
│
├── templates/                      # Templates for new configurations
│
├── docs/                           # Documentation
│   ├── tutorials/                  # Learning-oriented guides
│   ├── how-to/                     # Task-oriented guides
│   ├── reference/                  # Technical reference
│   └── explanation/                # Conceptual documentation
│
├── bundles.nix                     # Role and package definitions
├── flake.nix                       # Main Nix flake definition
├── flake.lock                      # Locked dependencies
├── devenv.nix                      # Development environment
├── devenv.yaml                     # Devenv configuration
├── bootstrap.sh                    # Bootstrap script
├── README.md                       # Project overview
└── AGENTS.md                       # AI agent instructions
```

## Key Files

### flake.nix

Main entry point. Defines:
- System configurations (Darwin, NixOS)
- Helper functions (`mkUser`, `mkBundleModule`, etc.)
- Input dependencies

### bundles.nix

Role definitions. Contains:
- `roles` attribute with all available roles
- Package lists per role
- Platform-specific packages

### devenv.nix

Development environment. Contains:
- Task definitions
- Pre-commit hooks
- Development tools

### modules/common/options.nix

Configuration options. Defines:
- `myConfig` option namespace
- Type-safe configuration schema
- Default values

### modules/home-manager/skills/manifest.nix

Skills registry. Contains:
- All available skills
- Role assignments
- Source locations
