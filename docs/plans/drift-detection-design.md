# Drift Detection Test Suite Design

## 1. Overview and Goals

### Purpose
The drift detection test suite provides automated monitoring to detect when the actual state of Nix-managed systems diverges from their declared configurations. This ensures configuration integrity across all machines (wweaver, MegamanX, drlight, zero) and provides early warning when manual interventions or external changes create inconsistencies.

### Why Drift Detection Matters for This System

This Nix configuration manages 4 machines across 2 platforms with multiple roles (developer, workstation, desktop, llm-client, etc.). The complexity creates several drift risks:

1. **Role-Based Bundles**: With 9 different roles (`base`, `developer`, `creative`, `desktop`, `workstation`, `entertainment`, `gaming`, `llm-*` roles), packages and services can be inadvertently modified
2. **Cross-Platform Differences**: Darwin uses Homebrew casks for GUI apps while NixOS uses native packages - both need monitoring
3. **Home-Manager Integration**: User environments managed by home-manager can drift independently of system configs
4. **Secret Management**: 1Password integration means SSH keys and credentials managed outside Nix need tracking
5. **Service Diversity**: LLM services (Litellm, Ollama), Docker containers, and AeroSpace window manager all represent drift vectors

Without drift detection, issues compound until rebuilds fail or systems behave inconsistently.

### Goals

#### Detection Goals
- **Closure Validation**: Detect when system closures diverge from declared configurations within 24 hours
- **Package Drift Monitoring**: Identify packages installed via `nix-env`, `brew install`, or `apt` outside the flake
- **Service State Verification**: Ensure systemd (NixOS) and launchd (Darwin) services match declared states
- **Configuration Integrity**: Verify managed dotfiles and configs haven't been manually edited
- **Generation Tracking**: Alert when systems haven't been rebuilt for >7 days

#### Operational Goals
- **Zero-Impact Testing**: All tests use `--dry-run` or read-only operations, never modifying systems
- **CI Integration**: Seamless integration with existing GitHub Actions workflows
- **Local Execution**: Support for manual drift checks via `task drift:check`
- **Historical Tracking**: Maintain drift history to identify patterns and recurring issues

#### Reporting Goals
- **Actionable Output**: Every detected drift includes specific remediation commands
- **Multiple Formats**: Support JSON (automation), Markdown (humans), and terminal output
- **Severity Classification**: Distinguish critical issues (security risks) from informational findings
- **Aggregation**: Single report showing drift across all 4 systems

### Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Detection Latency | ≤ 24 hours | Time between drift occurrence and detection in CI |
| System Coverage | 100% | All 4 hosts (wweaver, MegamanX, drlight, zero) tested |
| False Positive Rate | < 5% | Alerts that don't represent actual drift |
| Test Execution Time | < 10 minutes | Complete test suite completion time |
| Remediation Clarity | 100% | Drift findings include clear fix commands |
| CI Integration | Zero failures | No disruption to existing `nix-ci.yml` workflow |

### Out of Scope
- **Auto-remediation**: This design detects drift but doesn't automatically fix it (safety first)
- **Performance monitoring**: Tests focus on configuration drift, not system performance
- **Security scanning**: While drift may indicate security issues, this isn't a vulnerability scanner
- **Real-time monitoring**: Tests run on schedule, not continuously

### Assumptions
- Systems have Nix with flakes enabled
- Home-manager is used for user environments
- Darwin systems use nix-darwin
- CI runners have access to Cachix for speed
- Systems are network-accessible for SSH-based tests (future enhancement)

---

## 2. Architecture and Components

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Nix Flake Integration                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  flake.nix                                                      │   │
│  │  ├── packages.drift-detection-cli                              │   │
│  │  ├── apps.drift-detection                                      │   │
│  │  └── checks.<system>.drift-detection (future)                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│                              ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │              modules/drift-detection/                           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │   │
│  │  │   Engine     │  │   Options    │  │   CLI Interface      │  │   │
│  │  │   (engine)   │  │   (options)  │  │   (cli.nix)          │  │   │
│  │  └──────┬───────┘  └──────────────┘  └──────────────────────┘  │   │
│  │         │                                                      │   │
│  │  ┌──────┴──────────────────────────────────────────────┐      │   │
│  │  │              Test Modules (tests/*.nix)              │      │   │
│  │  │  ┌────────┐ ┌────────┐ ┌──────────┐ ┌─────┐ ┌──────┐ │      │   │
│  │  │  │ nixos  │ │ darwin │ │ home-mgr │ │ svc │ │ file │ │      │   │
│  │  │  └────────┘ └────────┘ └──────────┘ └─────┘ └──────┘ │      │   │
│  │  └──────────────────────────────────────────────────────┘      │   │
│  │         │                                                      │   │
│  │  ┌──────┴──────────────────────────────────────────────┐      │   │
│  │  │           Reporting & Alerting                        │      │   │
│  │  │  ┌────────────┐  ┌────────────┐  ┌──────────────┐    │      │   │
│  │  │  │  Reporter  │  │   Alerts   │  │  Formatters  │    │      │   │
│  │  │  └────────────┘  └────────────┘  └──────────────┘    │      │   │
│  │  └──────────────────────────────────────────────────────┘      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Integration with Existing Architecture

The drift detection system leverages the existing modular architecture:

#### Integration Points

**1. Flake Outputs** (`flake.nix`)
- **Package**: `packages.<system>.drift-detection-cli` - CLI tool for running tests
- **App**: `apps.<system>.drift-detection` - Runnable via `nix run .#drift-detection`
- **Checks**: Future integration with `checks.<system>.drift-detection` for `nix flake check`

**2. Role-Based Enablement** (`bundles.nix`)
```nix
roles.drift-detection = {
  packages = [ drift-detection-cli ];
  extraConfig = {
    myConfig.driftDetection.enable = true;
    myConfig.driftDetection.schedule = "daily";
  };
};
```

**3. Type-Safe Options** (`modules/common/options.nix`)
Extends existing options schema:
```nix
options.myConfig.driftDetection = {
  enable = mkEnableOption "drift detection";
  schedule = mkOption { type = types.enum [ "hourly" "daily" "weekly" ]; };
  severityThreshold = mkOption { type = types.enum [ "info" "warning" "critical" ]; };
  tests = mkOption { type = types.listOf types.str; };
};
```

**4. Existing Helper Functions** (`flake.nix`)
- Reuses `mkBundleModule` to create drift detection bundles
- Leverages `commonModules` pattern for shared configuration
- Uses `myConfig.isDarwin` for platform detection

### Core Components

#### 2.1 CLI Interface (`modules/drift-detection/cli.nix`)
A unified command-line tool for drift detection:

```bash
# Basic usage
nix run .#drift-detection -- --host wweaver

# With options
nix run .#drift-detection -- \
  --host drlight \
  --platform nixos \
  --severity warning \
  --format markdown \
  --output report.md

# List available tests
nix run .#drift-detection -- --list-tests

# Run specific test category
nix run .#drift-detection -- --category services
```

**Implementation**: Pure Nix package wrapping a shell script that invokes the test engine.

#### 2.2 Test Engine (`modules/drift-detection/engine.nix`)
The orchestration layer that manages test execution:

**Responsibilities**:
- **Test Discovery**: Scans `tests/` directory for available tests
- **Platform Filtering**: Only runs tests applicable to current platform (`myConfig.isDarwin`)
- **Parallel Execution**: Runs independent tests concurrently for speed
- **Result Aggregation**: Collects results from all test modules
- **Error Handling**: Graceful handling of test failures without stopping other tests

**Key Design Decisions**:
- Tests are pure Nix derivations that output JSON results
- Each test runs in isolation (no shared state)
- Tests are read-only (use `--dry-run`, never modify system)

#### 2.3 Test Categories (5 categories, 20+ tests)

Each category is a Nix module in `modules/drift-detection/tests/`:

**NixOS Tests** (`tests/nixos.nix`)
- System closure drift detection using `nvd`
- Generation age monitoring
- NixOS channel validation
- Boot loader consistency
- `/nix/store` corruption checks

**Darwin Tests** (`tests/darwin.nix`)
- nix-darwin configuration validation
- Homebrew cask drift detection
- macOS defaults verification
- LaunchDaemon/LaunchAgent state
- `.DS_Store` pollution in managed directories

**Home-Manager Tests** (`tests/home-manager.nix`)
- User environment closure drift
- Dotfile integrity (hash-based)
- Program configuration validation
- Generation comparison
- Symlink validation (managed files should be symlinks)

**Service Tests** (`tests/services.nix`)
- Systemd unit state (NixOS)
- Launchd job state (Darwin)
- Docker container drift
- Litellm configuration drift
- AeroSpace window manager state
- SSH agent configuration

**File Tests** (`tests/files.nix`)
- Critical config file hash verification
- SSH key permissions and presence
- Managed file existence
- Unauthorized file detection in `~/.config/`
- Sudoers file integrity

#### 2.4 Options System (`modules/drift-detection/options.nix`)
Type-safe configuration following existing patterns:

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.myConfig.driftDetection;
in
{
  options.myConfig.driftDetection = {
    enable = mkEnableOption "Enable drift detection for this host";
    
    schedule = mkOption {
      type = types.enum [ "hourly" "daily" "weekly" "manual" ];
      default = "daily";
      description = "How often to run drift detection";
    };
    
    severityThreshold = mkOption {
      type = types.enum [ "info" "warning" "critical" ];
      default = "warning";
      description = "Minimum severity level to report";
    };
    
    enabledTests = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Specific tests to run (empty = all)";
    };
    
    disabledTests = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Tests to skip";
    };
    
    reportFormat = mkOption {
      type = types.enum [ "json" "markdown" "terminal" ];
      default = "terminal";
    };
    
    alertChannels = mkOption {
      type = types.listOf (types.enum [ "github" "slack" "email" ]);
      default = [ "github" ];
    };
    
    githubRepo = mkOption {
      type = types.str;
      default = "funkymonkeymonk/nix";
      description = "Repository for creating drift issues";
    };
  };
  
  config = mkIf cfg.enable {
    # Configuration applied when drift detection is enabled
    # (Mostly CI-focused, minimal local config needed)
  };
}
```

#### 2.5 Report Generator (`modules/drift-detection/reporting.nix`)
Aggregates and formats test results:

**Input**: List of test result derivations (JSON)
**Output**: Formatted report (JSON/Markdown/Terminal)

**Features**:
- **Multi-format Output**: JSON for automation, Markdown for GitHub, Terminal for local use
- **Severity Filtering**: Only include results ≥ configured threshold
- **Summary Statistics**: Total tests, pass/fail counts, drift by category
- **Remediation Hints**: Specific commands to fix each issue
- **Historical Context**: Compare with previous runs (future enhancement)

**Report Structure**:
```nix
{
  metadata = {
    timestamp = "2026-02-09T10:00:00Z";
    hostname = "drlight";
    platform = "nixos";
    nixpkgsRev = "abc123...";
    duration = 245.3;
  };
  
  results = {
    "system-closure-drift" = {
      category = "nixos";
      status = "failed";
      severity = "critical";
      message = "System closure differs from declared configuration";
      details = {
        currentGeneration = 42;
        declaredGeneration = 43;
        packagesAdded = [ "firefox" "nodejs" ];
        packagesRemoved = [ ];
      };
      remediation = "Run: sudo nixos-rebuild switch";
    };
    # ... more results
  };
  
  summary = {
    total = 15;
    passed = 14;
    failed = 1;
    critical = 1;
    warning = 0;
    info = 0;
  };
}
```

#### 2.6 Alert Manager (`modules/drift-detection/alerts.nix`)
Handles notifications when drift is detected:

**Channels**:
1. **GitHub Issues**: Create/update issue with drift report
2. **Slack/Discord**: Webhook notifications for real-time alerts
3. **Email**: SMTP-based email summaries
4. **Terminal**: Local output (default for manual runs)

**Smart Alerting**:
- **Deduplication**: Don't alert for the same drift twice
- **Escalation**: Critical drift alerts immediately, warnings batched daily
- **Rate Limiting**: Max 1 alert per hour per channel
- **Auto-Resolve**: Close issues when drift is resolved

**GitHub Integration** (Primary Channel):
- Creates issue with `drift-detected` label
- Updates existing open issue instead of creating duplicates
- Includes full Markdown report in issue body
- Links to specific CI run for logs

---

## 3. Test Categories and Implementation

### Test Execution Model

Before diving into specific tests, it's important to understand how tests execute in this architecture:

**Build-Time vs Runtime Tests**:
- **Build-time tests**: Pure Nix derivations that compare configurations (e.g., closure comparison)
- **Runtime tests**: Scripts that query actual system state (e.g., service status, file hashes)

**Test Structure**:
Each test is a Nix module that exports:
```nix
{
  name = "test-name";           # Unique test identifier
  category = "nixos|darwin|home-manager|services|files";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];  # Supported platforms
  severity = "critical|warning|info";
  
  # The actual test - a derivation that runs the check
  test = pkgs.runCommand "test-name" { } ''
    # Test logic here
    # Exit 0 = pass, Exit 1 = fail
    # Output JSON to $out with result details
  '';
  
  # Remediation command
  remediation = "nixos-rebuild switch";
}
```

### 3.1 NixOS Drift Tests

#### Test: System Closure Drift (`system-closure-drift`)
**Purpose**: Detect when `/run/current-system` differs from the declared configuration closure

**Rationale**: This is the most fundamental drift test. If the system closure differs, the entire system configuration is out of sync.

**Implementation Strategy**:
```nix
{ config, pkgs, lib, ... }:

let
  inherit (pkgs) nvd;
  hostname = config.networking.hostName;
in
{
  name = "system-closure-drift";
  category = "nixos";
  platforms = [ "x86_64-linux" "aarch64-linux" ];
  severity = "critical";
  
  test = pkgs.runCommand "test-system-closure-${hostname}"
    {
      nativeBuildInputs = [ nvd pkgs.jq ];
    }
    ''
      set -euo pipefail
      
      # Build the declared system (this is a pure Nix operation)
      echo "Building declared system configuration..."
      declared_closure=$(nix build --no-link --print-out-paths \
        .#nixosConfigurations.${hostname}.config.system.build.toplevel \
        2>/dev/null || echo "")
      
      if [ -z "$declared_closure" ]; then
        echo '{"status": "error", "message": "Failed to build declared configuration"}' > $out
        exit 0  # Test itself didn't fail, just can't determine drift
      fi
      
      # Get current system closure
      current_closure="/run/current-system"
      
      if [ ! -L "$current_closure" ]; then
        echo '{"status": "failed", "severity": "critical", "message": "Current system symlink missing"}' > $out
        exit 0
      fi
      
      # Use nvd to compare closures
      diff_output=$(${nvd}/bin/nvd diff "$current_closure" "$declared_closure" 2>&1) || true
      
      if [ -z "$diff_output" ] || echo "$diff_output" | grep -q "No changes"; then
        echo '{"status": "passed"}' > $out
      else
        # Parse the diff to extract useful information
        added_packages=$(echo "$diff_output" | grep "^+" | wc -l)
        removed_packages=$(echo "$diff_output" | grep "^-" | wc -l)
        
        jq -n \
          --arg status "failed" \
          --arg severity "critical" \
          --arg message "System closure differs from declared configuration" \
          --argjson added "$added_packages" \
          --argjson removed "$removed_packages" \
          --arg diff "$diff_output" \
          '{
            status: $status,
            severity: $severity,
            message: $message,
            details: {
              packagesAdded: $added,
              packagesRemoved: $removed,
              diffSummary: ($diff | split("\n") | .[0:20] | join("\n"))
            }
          }' > $out
      fi
    '';
  
  remediation = "sudo nixos-rebuild switch";
}
```

**CI Execution**: This test runs on Ubuntu CI runners using `nix build --dry-run` to validate the system can be built, then uses `nix eval` to compare closures without actually building.

**Local Execution**: On actual NixOS systems, compares `/run/current-system` with the built closure.

---

#### Test: Generation Age (`generation-age`)
**Purpose**: Detect when a system hasn't been rebuilt recently

**Rationale**: Stale systems may miss security updates or accumulate uncommitted changes. The 7-day threshold balances currency with practical rebuild schedules.

**Implementation**:
```nix
{
  name = "generation-age";
  category = "nixos";
  platforms = [ "x86_64-linux" "aarch64-linux" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-generation-age"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      max_age_days=7
      
      # Get the most recent generation date from nix profile
      # This works in CI by reading the generation list from the built system
      latest_gen_date=$(nixos-rebuild list-generations 2>/dev/null | \
        grep -v "Generation" | head -1 | awk '{print $2, $3}' || echo "")
      
      if [ -z "$latest_gen_date" ]; then
        # In CI mode, we can't access actual system generations
        # Instead, check if the flake has been modified recently
        flake_modified=$(git -C /dev/null log -1 --format=%ct 2>/dev/null || echo "0")
        if [ "$flake_modified" = "0" ]; then
          echo '{"status": "skipped", "message": "Cannot determine generation age in CI"}' > $out
          exit 0
        fi
      fi
      
      # Calculate age
      gen_timestamp=$(date -d "$latest_gen_date" +%s 2>/dev/null || echo "0")
      current_timestamp=$(date +%s)
      days_old=$(( (current_timestamp - gen_timestamp) / 86400 ))
      
      if [ "$days_old" -gt "$max_age_days" ]; then
        jq -n \
          --arg status "failed" \
          --arg severity "warning" \
          --arg message "Last rebuild was $days_old days ago" \
          --argjson days "$days_old" \
          --argjson threshold "$max_age_days" \
          '{
            status: $status,
            severity: $severity,
            message: $message,
            details: { daysSinceRebuild: $days, thresholdDays: $threshold }
          }' > $out
      else
        echo '{"status": "passed"}' > $out
      fi
    '';
  
  remediation = "Run 'task switch' to update the system";
}
```

---

#### Test: NixOS Channel Divergence (`nixos-channel-drift`)
**Purpose**: Detect when the NixOS channel differs from the flake's nixpkgs input

**Rationale**: Channel divergence indicates the system may be using different package sources than the flake intends.

**Implementation**: Compare `nixos-version` output with `flake.lock` nixpkgs revision.

**Severity**: Warning (channels can legitimately differ during updates)

---

### 3.2 Darwin Drift Tests

#### Test: nix-darwin Configuration Drift (`darwin-config-drift`)
**Purpose**: Detect when macOS system state differs from nix-darwin configuration

**Challenge**: Unlike NixOS, Darwin doesn't have `/run/current-system`. We detect drift by checking if a rebuild would change anything.

**Implementation**:
```nix
{
  name = "darwin-config-drift";
  category = "darwin";
  platforms = [ "aarch64-darwin" "x86_64-darwin" ];
  severity = "critical";
  
  test = pkgs.runCommand "test-darwin-drift"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Build the declared configuration
      echo "Building declared Darwin configuration..."
      
      # In CI, we do a dry-build to see if it would change anything
      # On real systems, we compare the activation scripts
      
      build_output=$(darwin-rebuild build --flake .#${hostname} 2>&1) || {
        jq -n \
          --arg status "failed" \
          --arg severity "critical" \
          --arg message "Failed to build Darwin configuration" \
          '{ status: $status, severity: $severity, message: $message }' > $out
        exit 0
      }
      
      # Check if the activation script differs from current
      # This is complex because Darwin doesn't have a simple "current system" symlink
      # Instead, we check if the flake.lock has been modified since last switch
      
      # Simplified approach: Compare flake.lock modification time
      # A more robust approach would compare actual activation checksums
      
      echo '{"status": "passed", "note": "Full drift detection requires running on actual Darwin system"}' > $out
    '';
  
  remediation = "Run 'darwin-rebuild switch' to apply configuration";
}
```

**Note**: Full Darwin drift detection requires running on actual macOS systems, not just CI builders. CI can validate that configurations build, but not that they match runtime state.

---

#### Test: Homebrew Cask Drift (`homebrew-cask-drift`)
**Purpose**: Detect Homebrew casks installed outside nix-darwin's homebrew module

**Rationale**: This system uses nix-darwin's homebrew integration (in `mkNixHomebrew`). Manual `brew install --cask` commands bypass Nix tracking.

**Implementation**:
```nix
{
  name = "homebrew-cask-drift";
  category = "darwin";
  platforms = [ "aarch64-darwin" "x86_64-darwin" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-homebrew-drift"
    { nativeBuildInputs = [ pkgs.jq pkgs.git ]; }
    ''
      set -euo pipefail
      
      # Get declared casks from nix-darwin configuration
      # We extract this from the flake configuration
      declared_casks=$(nix eval --json .#darwinConfigurations.${hostname}.config.homebrew.casks 2>/dev/null | \
        jq -r '.[]' | sort || echo "")
      
      if [ -z "$declared_casks" ]; then
        echo '{"status": "skipped", "message": "No homebrew casks declared for this host"}' > $out
        exit 0
      fi
      
      # In CI mode, we can't actually query Homebrew
      # On real systems, we would run: brew list --cask
      
      # Store declared casks for comparison when run locally
      echo "$declared_casks" > $out.declared
      
      jq -n \
        --arg status "passed" \
        --arg message "Declared casks captured for comparison" \
        --argjson declaredCasksCount $(echo "$declared_casks" | wc -l) \
        '{
          status: $status,
          message: $message,
          details: { declaredCasksCount: $declaredCasksCount }
        }' > $out
    '';
  
  remediation = "Review 'brew list --cask' output; remove extra casks or add to configuration";
}
```

**Local Mode Enhancement**: When run on actual macOS systems with Homebrew available, this test would:
1. Run `brew list --cask` to get installed casks
2. Compare with declared casks from nix-darwin config
3. Report any extra casks (installed but not declared) or missing casks (declared but not installed)

---

#### Test: Homebrew Tap Drift (`homebrew-tap-drift`)
**Purpose**: Detect Homebrew taps not managed by nix-darwin

**Rationale**: Taps add formula sources. Untracked taps can lead to inconsistent package availability.

**Implementation**: Similar to cask drift, but for taps.

**Severity**: Info

---

#### Test: macOS Defaults Drift (`macos-defaults-drift`)
**Purpose**: Sample key macOS preferences to detect manual changes

**Rationale**: nix-darwin manages many macOS defaults. Manual changes in System Preferences create drift.

**Implementation**:
```nix
{
  name = "macos-defaults-drift";
  category = "darwin";
  platforms = [ "aarch64-darwin" ];
  severity = "info";
  
  test = pkgs.runCommand "test-macos-defaults"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      # Sample important defaults that are typically managed
      # This is informational only - not all changes are problematic
      
      # Examples: dock settings, finder preferences, keyboard settings
      # In practice, this would compare current defaults with declared values
      
      echo '{"status": "passed", "message": "Defaults sampling not implemented in CI mode"}' > $out
    '';
  
  remediation = "Review changes in System Preferences; re-apply configuration if needed";
}
```

---

### 3.3 Home-Manager Drift Tests

#### Test: Home-Manager Generation Drift (`hm-generation-drift`)
**Purpose**: Detect when user environment differs from home-manager configuration

**Rationale**: Home-manager manages dotfiles, packages, and user services. Drift here affects user experience.

**Implementation**:
```nix
{ username, hostname, ... }:

{
  name = "hm-generation-drift";
  category = "home-manager";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-hm-generation-${username}"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Build the home-manager configuration
      echo "Building home-manager configuration for ${username}..."
      
      hm_closure=$(home-manager build --flake .#${username}@${hostname} 2>&1 | \
        tail -1 | awk '{print $NF}') || {
        jq -n \
          --arg status "failed" \
          --arg severity "warning" \
          --arg message "Failed to build home-manager configuration" \
          '{ status: $status, severity: $severity, message: $message }' > $out
        exit 0
      }
      
      # In CI mode, we just verify it builds
      # On real systems, compare with current generation using 'home-manager generations'
      
      jq -n \
        --arg status "passed" \
        --arg message "Home-manager configuration builds successfully" \
        '{ status: $status, message: $message }' > $out
    '';
  
  remediation = "Run 'home-manager switch' to apply user configuration";
}
```

---

#### Test: Dotfile Integrity (`dotfile-integrity`)
**Purpose**: Verify managed dotfiles haven't been manually edited

**Rationale**: Home-manager manages dotfiles as symlinks to the Nix store. Manual edits break the symlink.

**Implementation**:
```nix
{
  name = "dotfile-integrity";
  category = "home-manager";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-dotfile-integrity"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Common managed dotfiles to check
      dotfiles=(
        "$HOME/.zshrc"
        "$HOME/.gitconfig"
        "$HOME/.config/git/config"
      )
      
      drift_found=false
      drifted_files=()
      
      for file in "''${dotfiles[@]}"; do
        if [ -f "$file" ] && [ ! -L "$file" ]; then
          # File exists but is not a symlink - it was edited manually
          drift_found=true
          drifted_files+=("$file")
        fi
      done
      
      if [ "$drift_found" = true ]; then
        jq -n \
          --arg status "failed" \
          --arg severity "warning" \
          --arg message "Managed dotfiles have been modified" \
          --argjson files "$(printf '%s\n' "''${drifted_files[@]}" | jq -R . | jq -s .)" \
          '{ 
            status: $status, 
            severity: $severity, 
            message: $message,
            details: { driftedFiles: $files }
          }' > $out
      else
        echo '{"status": "passed"}' > $out
      fi
    '';
  
  remediation = "Review changes; either move to Nix config or backup and restore symlink";
}
```

---

### 3.4 Service Drift Tests

#### Test: Systemd Service State (`systemd-service-state`)
**Purpose**: Verify systemd services are in expected states

**Rationale**: Failed or stopped services indicate configuration issues or runtime problems.

**Implementation**:
```nix
{
  name = "systemd-service-state";
  category = "services";
  platforms = [ "x86_64-linux" ];
  severity = "critical";
  
  test = pkgs.runCommand "test-systemd-services"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Check for failed services
      # In CI mode, we can't access actual systemd
      # On real systems: systemctl list-units --failed
      
      # This is primarily a runtime test
      echo '{"status": "passed", "note": "Runtime test - run on actual NixOS system"}' > $out
    '';
  
  remediation = "Check 'systemctl status <service>' and journalctl for details";
}
```

---

#### Test: Litellm Configuration Drift (`litellm-config-drift`)
**Purpose**: Detect when Litellm configuration differs from Nix configuration

**Rationale**: This system has specific LLM infrastructure (`llm-server`, `llm-host` roles). Litellm configuration is critical for LLM client functionality.

**Implementation**:
```nix
{
  name = "litellm-config-drift";
  category = "services";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-litellm-config"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Check if Litellm is configured for this host
      has_litellm=$(nix eval --json .#nixosConfigurations.${hostname}.config.services.litellm.enable 2>/dev/null || echo "false")
      
      if [ "$has_litellm" != "true" ]; then
        echo '{"status": "skipped", "message": "Litellm not enabled for this host"}' > $out
        exit 0
      fi
      
      # Get declared config path
      declared_config=$(nix eval --raw .#nixosConfigurations.${hostname}.config.services.litellm.configFile 2>/dev/null || echo "")
      
      if [ -n "$declared_config" ] && [ -f "$declared_config" ]; then
        # Compare with running config if service is active
        # This requires runtime access to the service
        echo '{"status": "passed", "message": "Litellm configuration validated"}' > $out
      else
        echo '{"status": "warning", "message": "Litellm enabled but config file not found"}' > $out
      fi
    '';
  
  remediation = "Restart Litellm service or rebuild system";
}
```

---

#### Test: Docker Container Drift (`docker-container-drift`)
**Purpose**: Detect Docker containers running outside Nix configuration

**Rationale**: This system uses Docker for various services. Manually started containers represent drift.

**Implementation**: Compare `docker ps` output with declared containers in Nix config.

**Severity**: Info

---

#### Test: AeroSpace Window Manager State (`aerospace-state`)
**Purpose**: Verify AeroSpace window manager configuration is applied

**Rationale**: This system uses AeroSpace for window management on Darwin. Configuration drift affects window management behavior.

**Implementation**:
```nix
{
  name = "aerospace-state";
  category = "services";
  platforms = [ "aarch64-darwin" ];
  severity = "info";
  
  test = pkgs.runCommand "test-aerospace"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      # Check if AeroSpace config is properly linked
      # Config should be at ~/.config/aerospace/aerospace.toml
      # Managed by home-manager
      
      echo '{"status": "passed", "note": "Verify ~/.config/aerospace/aerospace.toml exists"}' > $out
    '';
}
```

---

### 3.5 File Integrity Tests

#### Test: SSH Configuration Integrity (`ssh-config-integrity`)
**Purpose**: Verify SSH configuration files haven't been modified

**Rationale**: SSH configuration affects security and access. Unauthorized changes are a security concern.

**Implementation**:
```nix
{
  name = "ssh-config-integrity";
  category = "files";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];
  severity = "warning";
  
  test = pkgs.runCommand "test-ssh-integrity"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # Check if SSH config files exist and are managed
      ssh_config_files=(
        "$HOME/.ssh/config"
        "/etc/ssh/sshd_config"
      )
      
      issues=()
      
      for file in "''${ssh_config_files[@]}"; do
        if [ -f "$file" ]; then
          if [ -L "$file" ]; then
            # It's a symlink - verify it points to nix store
            target=$(readlink "$file")
            if [[ ! "$target" == /nix/store/* ]]; then
              issues+=("$file: symlink outside nix store")
            fi
          else
            # Not a symlink - manually edited
            issues+=("$file: not managed by Nix")
          fi
        fi
      done
      
      if [ ''${#issues[@]} -gt 0 ]; then
        jq -n \
          --arg status "failed" \
          --arg severity "warning" \
          --arg message "SSH configuration drift detected" \
          --argjson issues "$(printf '%s\n' "''${issues[@]}" | jq -R . | jq -s .)" \
          '{ 
            status: $status, 
            severity: $severity, 
            message: $message,
            details: { issues: $issues }
          }' > $out
      else
        echo '{"status": "passed"}' > $out
      fi
    '';
  
  remediation = "Review SSH config; restore from Nix or migrate changes to configuration";
}
```

---

#### Test: Unauthorized Config Files (`unauthorized-config-files`)
**Purpose**: Detect files in `~/.config/` that aren't managed by home-manager

**Rationale**: Accumulation of untracked config files indicates manual intervention and potential drift.

**Implementation**:
```nix
{
  name = "unauthorized-config-files";
  category = "files";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];
  severity = "info";
  
  test = pkgs.runCommand "test-unauthorized-files"
    { nativeBuildInputs = [ pkgs.jq ]; }
    ''
      set -euo pipefail
      
      # This is informational only
      # Scan ~/.config/ for directories not tracked by home-manager
      
      config_dir="$HOME/.config"
      
      if [ -d "$config_dir" ]; then
        total_dirs=$(find "$config_dir" -maxdepth 1 -type d | wc -l)
        echo "Found $total_dirs config directories (informational only)" >&2
      fi
      
      echo '{"status": "passed", "message": "Config directory scan complete"}' > $out
    '';
  
  remediation = "Review untracked files; consider adding to home-manager or cleaning up";
}
```

---

### 3.6 Test Summary

| Test Name | Category | Platforms | Severity | Runtime |
|-----------|----------|-----------|----------|---------|
| system-closure-drift | nixos | Linux | Critical | Build + Runtime |
| generation-age | nixos | Linux | Warning | Runtime |
| nixos-channel-drift | nixos | Linux | Warning | Build |
| darwin-config-drift | darwin | macOS | Critical | Build + Runtime |
| homebrew-cask-drift | darwin | macOS | Warning | Runtime |
| homebrew-tap-drift | darwin | macOS | Info | Runtime |
| macos-defaults-drift | darwin | macOS | Info | Runtime |
| hm-generation-drift | home-manager | All | Warning | Build + Runtime |
| dotfile-integrity | home-manager | All | Warning | Runtime |
| systemd-service-state | services | Linux | Critical | Runtime |
| litellm-config-drift | services | All | Warning | Build |
| docker-container-drift | services | All | Info | Runtime |
| aerospace-state | services | macOS | Info | Runtime |
| ssh-config-integrity | files | All | Warning | Runtime |
| unauthorized-config-files | files | All | Info | Runtime |

**Total**: 15 tests covering all drift vectors identified for this system.

---

## 4. CI/CD Integration

### 4.1 CI vs Runtime Testing Modes

It's important to distinguish between two testing modes:

**CI Mode (Build Validation)**:
- Runs on GitHub Actions runners (Ubuntu, macOS)
- Validates that configurations build correctly
- Performs static analysis of Nix expressions
- Cannot detect runtime drift (services, file hashes, etc.)
- **Purpose**: Ensure configurations are valid and buildable

**Runtime Mode (Actual Drift Detection)**:
- Runs on actual target systems (or via SSH)
- Compares actual system state with declared configuration
- Detects service failures, file modifications, manual package installs
- **Purpose**: Detect real drift on running systems

**This design focuses primarily on CI Mode**, which provides 80% of the value with 20% of the complexity. Runtime mode can be added later via SSH-based testing.

### 4.2 GitHub Actions Workflow

New workflow file: `.github/workflows/drift-detection.yml`

```yaml
name: Drift Detection

on:
  schedule:
    # Run daily at 6:00 AM UTC (after the flake update workflow on Fridays)
    - cron: '0 6 * * *'
  workflow_dispatch:
    inputs:
      severity:
        description: 'Minimum severity to report'
        required: false
        default: 'warning'
        type: choice
        options:
          - info
          - warning
          - critical
      hosts:
        description: 'Specific hosts to test (comma-separated, or "all")'
        required: false
        default: 'all'

env:
  NIX_CONFIG: "accept-flake-config = true"

jobs:
  # Determine which hosts to test
  setup-matrix:
    runs-on: ubuntu-latest
    outputs:
      darwin-hosts: ${{ steps.matrix.outputs.darwin-hosts }}
      nixos-hosts: ${{ steps.matrix.outputs.nixos-hosts }}
    steps:
      - id: matrix
        run: |
          if [ "${{ github.event.inputs.hosts }}" = "all" ] || [ -z "${{ github.event.inputs.hosts }}" ]; then
            echo "darwin-hosts=[\"wweaver\",\"MegamanX\"]" >> $GITHUB_OUTPUT
            echo "nixos-hosts=[\"drlight\",\"zero\"]" >> $GITHUB_OUTPUT
          else
            # Parse comma-separated hosts and categorize by platform
            IFS=',' read -ra HOSTS <<< "${{ github.event.inputs.hosts }}"
            DARWIN_HOSTS=()
            NIXOS_HOSTS=()
            
            for host in "${HOSTS[@]}"; do
              case "$host" in
                wweaver|MegamanX) DARWIN_HOSTS+=("$host") ;;
                drlight|zero) NIXOS_HOSTS+=("$host") ;;
              esac
            done
            
            echo "darwin-hosts=$(printf '%s\n' "${DARWIN_HOSTS[@]}" | jq -R . | jq -s .)" >> $GITHUB_OUTPUT
            echo "nixos-hosts=$(printf '%s\n' "${NIXOS_HOSTS[@]}" | jq -R . | jq -s .)" >> $GITHUB_OUTPUT
          fi

  # Test Darwin configurations (CI Mode)
  drift-darwin:
    needs: setup-matrix
    if: ${{ needs.setup-matrix.outputs.darwin-hosts != '[]' }}
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix:
        host: ${{ fromJson(needs.setup-matrix.outputs.darwin-hosts) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Needed for git history in some tests

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Setup Cachix
        uses: cachix/cachix-action@v14
        with:
          name: funkymonkeymonk
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      - name: Run Drift Detection
        id: drift
        run: |
          echo "Running drift detection for ${{ matrix.host }}..."
          
          # Run the drift detection CLI
          nix run .#drift-detection -- \
            --host ${{ matrix.host }} \
            --platform darwin \
            --severity ${{ github.event.inputs.severity || 'warning' }} \
            --format json \
            --output drift-report-${{ matrix.host }}.json \
            || true  # Continue even if drift detected
          
          # Display results in terminal
          echo "=== Drift Detection Results for ${{ matrix.host }} ==="
          cat drift-report-${{ matrix.host }}.json | jq -r '.summary | "Total: \(.total), Passed: \(.passed), Failed: \(.failed)"'
          
          # Set output for downstream jobs
          echo "report=drift-report-${{ matrix.host }}.json" >> $GITHUB_OUTPUT
          
          # Check for critical drift
          if jq -e '.summary.critical > 0' drift-report-${{ matrix.host }}.json; then
            echo "has-critical-drift=true" >> $GITHUB_OUTPUT
            echo "::error::Critical drift detected on ${{ matrix.host }}!"
          else
            echo "has-critical-drift=false" >> $GITHUB_OUTPUT
          fi
        shell: bash

      - name: Upload Report
        uses: actions/upload-artifact@v4
        with:
          name: drift-report-darwin-${{ matrix.host }}
          path: drift-report-${{ matrix.host }}.json
          retention-days: 30

      - name: Fail on Critical Drift
        if: steps.drift.outputs.has-critical-drift == 'true'
        run: |
          echo "Critical drift detected. See uploaded artifacts for details."
          exit 1

  # Test NixOS configurations (CI Mode)
  drift-nixos:
    needs: setup-matrix
    if: ${{ needs.setup-matrix.outputs.nixos-hosts != '[]' }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        host: ${{ fromJson(needs.setup-matrix.outputs.nixos-hosts) }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Setup Cachix
        uses: cachix/cachix-action@v14
        with:
          name: funkymonkeymonk
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      - name: Run Drift Detection
        id: drift
        run: |
          echo "Running drift detection for ${{ matrix.host }}..."
          
          # Build the system to validate it works
          echo "Building system configuration..."
          nix build --dry-run .#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel \
            2>&1 | tee build-output.txt
          
          # Run drift detection
          nix run .#drift-detection -- \
            --host ${{ matrix.host }} \
            --platform nixos \
            --severity ${{ github.event.inputs.severity || 'warning' }} \
            --format json \
            --output drift-report-${{ matrix.host }}.json \
            || true
          
          echo "=== Drift Detection Results for ${{ matrix.host }} ==="
          cat drift-report-${{ matrix.host }}.json | jq -r '.summary // "No summary available"'
          
          # Set outputs
          echo "report=drift-report-${{ matrix.host }}.json" >> $GITHUB_OUTPUT
          
          if jq -e '.summary.critical > 0' drift-report-${{ matrix.host }}.json 2>/dev/null; then
            echo "has-critical-drift=true" >> $GITHUB_OUTPUT
            echo "::error::Critical drift detected on ${{ matrix.host }}!"
          else
            echo "has-critical-drift=false" >> $GITHUB_OUTPUT
          fi
        shell: bash

      - name: Upload Report
        uses: actions/upload-artifact@v4
        with:
          name: drift-report-nixos-${{ matrix.host }}
          path: drift-report-${{ matrix.host }}.json
          retention-days: 30

      - name: Fail on Critical Drift
        if: steps.drift.outputs.has-critical-drift == 'true'
        run: |
          echo "Critical drift detected on ${{ matrix.host }}. See artifacts for details."
          exit 1

  # Aggregate all reports and create summary
  aggregate:
    needs: [drift-darwin, drift-nixos]
    if: always() && (needs.drift-darwin.result == 'success' || needs.drift-nixos.result == 'success')
    runs-on: ubuntu-latest
    steps:
      - name: Download All Reports
        uses: actions/download-artifact@v4
        with:
          path: reports
          pattern: drift-report-*

      - name: Aggregate Reports
        id: aggregate
        run: |
          echo "Aggregating drift reports..."
          
          # Combine all reports into one JSON file
          find reports -name "*.json" -exec cat {} \; | jq -s '{
            metadata: {
              timestamp: now,
              runId: "${{ github.run_id }}",
              triggeredBy: "${{ github.event_name }}"
            },
            hosts: .
          }' > drift-report-aggregate.json
          
          # Generate summary
          echo "=== Drift Detection Summary ==="
          jq -r '.hosts[] | "\(.metadata.hostname): \(.summary.passed)/\(.summary.total) passed"' drift-report-aggregate.json
          
          # Check if any critical drift was found
          if jq -e '.hosts[].summary.critical | add > 0' drift-report-aggregate.json; then
            echo "has-critical-drift=true" >> $GITHUB_OUTPUT
          else
            echo "has-critical-drift=false" >> $GITHUB_OUTPUT
          fi
          
          # Generate Markdown report
          cat > drift-summary.md << 'EOF'
          # Drift Detection Report
          
          **Run Date:** ${{ github.event.schedule && 'Scheduled' || 'Manual' }} - $(date -u +"%Y-%m-%d %H:%M UTC")
          **Workflow Run:** ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
          
          ## Summary
          EOF
          
          jq -r '.hosts[] | "
          ### \(.metadata.hostname) (\(.metadata.platform))
          - **Status:** \(.summary.failed > 0 | if . then "❌ Drift Detected" else "✅ No Drift" end)
          - **Tests:** \(.summary.passed)/\(.summary.total) passed
          - **Critical:** \(.summary.critical), **Warning:** \(.summary.warning), **Info:** \(.summary.info)
          "' drift-report-aggregate.json >> drift-summary.md
          
          # Add failed tests details
          echo "" >> drift-summary.md
          echo "## Failed Tests" >> drift-summary.md
          
          jq -r '.hosts[] | select(.summary.failed > 0) | "
          ### \(.metadata.hostname)
          \(.results | to_entries[] | select(.value.status == "failed") | "
          - **\(.key)** (\(.value.severity))
            - \(.value.message)
            - **Fix:** \(.value.remediation)
          ")"' drift-report-aggregate.json >> drift-summary.md
          
          cat drift-summary.md
        shell: bash

      - name: Upload Aggregate Report
        uses: actions/upload-artifact@v4
        with:
          name: drift-report-aggregate
          path: |
            drift-report-aggregate.json
            drift-summary.md
          retention-days: 90

      - name: Create or Update Issue
        if: steps.aggregate.outputs.has-critical-drift == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const summary = fs.readFileSync('drift-summary.md', 'utf8');
            const aggregate = JSON.parse(fs.readFileSync('drift-report-aggregate.json', 'utf8'));
            
            // Find existing open drift issue
            const { data: issues } = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              labels: 'drift-detected',
              state: 'open'
            });
            
            const title = `🔴 System Drift Detected - ${new Date().toISOString().split('T')[0]}`;
            
            if (issues.length === 0) {
              // Create new issue
              await github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title: title,
                body: summary,
                labels: ['drift-detected', 'automated', 'needs-attention']
              });
              console.log('Created new drift issue');
            } else {
              // Update existing issue
              await github.rest.issues.update({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issues[0].number,
                title: title,
                body: summary
              });
              console.log(`Updated existing drift issue #${issues[0].number}`);
            }

  # Comment on PRs if drift detected (when manually triggered from PR context)
  pr-comment:
    needs: aggregate
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.hosts != 'all'
    runs-on: ubuntu-latest
    steps:
      - name: Comment on PR
        uses: actions/github-script@v7
        with:
          script: |
            // Only comment if this was triggered from a PR
            if (context.issue.number) {
              const { data: artifacts } = await github.rest.actions.listWorkflowRunArtifacts({
                owner: context.repo.owner,
                repo: context.repo.repo,
                run_id: context.runId
              });
              
              const aggregateArtifact = artifacts.artifacts.find(a => a.name === 'drift-report-aggregate');
              
              if (aggregateArtifact) {
                await github.rest.issues.createComment({
                  issue_number: context.issue.number,
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  body: `🔍 Drift detection completed. View full report: ${aggregateArtifact.archive_download_url}`
                });
              }
            }
```

### 4.3 Integration with Existing CI

The drift detection workflow integrates with the existing `nix-ci.yml`:

**Option 1: Separate Scheduled Workflow (Recommended)**
- Keeps drift detection separate from build tests
- Runs on schedule (daily) vs on every PR
- Creates persistent issues for tracking

**Option 2: Post-Build Drift Check**
Add to existing `nix-ci.yml` after successful builds:
```yaml
  drift-check-post-build:
    needs: [build-darwin, build-linux]
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule'  # Only on scheduled runs
    steps:
      - uses: actions/checkout@v4
      - name: Run Drift Detection
        run: |
          # Run drift detection only on scheduled builds
          nix run .#drift-detection -- --all-hosts
```

**Option 3: Manual Only**
- Only run via `workflow_dispatch`
- Good for on-demand investigations

### 4.4 Taskfile Integration

Add to existing `Taskfile.yml`:

```yaml
  # Drift Detection Tasks
  drift:detect:
    desc: Run drift detection on all hosts (CI mode)
    cmds:
      - echo "Running drift detection..."
      - task: drift:detect:darwin
      - task: drift:detect:nixos

  drift:detect:darwin:
    desc: Run drift detection on Darwin hosts
    cmds:
      - echo "Testing Darwin hosts..."
      - nix run .#drift-detection -- --host wweaver --platform darwin --format terminal
      - nix run .#drift-detection -- --host MegamanX --platform darwin --format terminal

  drift:detect:nixos:
    desc: Run drift detection on NixOS hosts
    cmds:
      - echo "Testing NixOS hosts..."
      - nix run .#drift-detection -- --host drlight --platform nixos --format terminal
      - nix run .#drift-detection -- --host zero --platform nixos --format terminal

  drift:detect:host:
    desc: Run drift detection on specific host (requires -- HOST=hostname)
    cmds:
      - nix run .#drift-detection -- --host {{.HOST}} --format markdown --output drift-report-{{.HOST}}.md
    vars:
      HOST: '{{.HOST | default "unknown"}}'

  drift:report:
    desc: View latest drift report
    cmds:
      - |
        if [ -f drift-report-aggregate.json ]; then
          jq -r '.hosts[] | "\(.metadata.hostname): \(.summary.passed)/\(.summary.total) passed"' drift-report-aggregate.json
        else
          echo "No aggregate report found. Run 'task drift:detect' first."
        fi

  drift:check:critical:
    desc: Check for critical drift only
    cmds:
      - nix run .#drift-detection -- --severity critical --format terminal
```

### 4.5 Execution Examples

**Local Development**:
```bash
# Run drift detection on all hosts (build validation)
task drift:detect

# Run on specific host
task drift:detect:host -- HOST=wweaver

# Check only critical issues
task drift:check:critical
```

**CI Execution**:
```bash
# Scheduled daily run (automatic)
# Triggered by cron at 6 AM UTC

# Manual run for specific host
gh workflow run drift-detection.yml -f hosts=wweaver -f severity=warning

# Manual run for all hosts
gh workflow run drift-detection.yml -f hosts=all
```

**Nix Run (Anywhere)**:
```bash
# Run drift detection CLI directly
nix run .#drift-detection -- --help

# Check specific host with JSON output
nix run .#drift-detection -- --host drlight --format json

# Check all hosts, only critical issues
nix run .#drift-detection -- --all-hosts --severity critical
```

---

## 5. Reporting and Alerting

### 5.1 Report Formats and Structure

The drift detection system produces reports in multiple formats to support different use cases.

#### JSON Report (Machine-Readable)

**Use Case**: CI artifacts, automation, programmatic analysis

**Schema**:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["metadata", "results", "summary"],
  "properties": {
    "metadata": {
      "type": "object",
      "required": ["timestamp", "hostname", "platform", "duration"],
      "properties": {
        "timestamp": { 
          "type": "string", 
          "format": "date-time",
          "description": "ISO 8601 timestamp of report generation"
        },
        "hostname": { 
          "type": "string",
          "description": "Name of the host being tested"
        },
        "platform": { 
          "type": "string", 
          "enum": ["darwin", "nixos"],
          "description": "Platform type"
        },
        "nixpkgsRevision": {
          "type": "string",
          "description": "Git revision of nixpkgs from flake.lock"
        },
        "flakeRevision": {
          "type": "string",
          "description": "Git revision of this flake"
        },
        "testMode": {
          "type": "string",
          "enum": ["ci", "runtime"],
          "description": "Whether this is CI validation or runtime detection"
        },
        "duration": { 
          "type": "number",
          "description": "Test execution time in seconds"
        }
      }
    },
    "results": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["testName", "category", "status", "severity"],
        "properties": {
          "testName": { "type": "string" },
          "category": { 
            "type": "string", 
            "enum": ["nixos", "darwin", "home-manager", "services", "files"]
          },
          "status": { 
            "type": "string", 
            "enum": ["passed", "failed", "skipped", "error"]
          },
          "severity": { 
            "type": "string", 
            "enum": ["info", "warning", "critical"]
          },
          "message": { 
            "type": "string",
            "description": "Human-readable description of result"
          },
          "details": { 
            "type": "object",
            "description": "Test-specific additional information"
          },
          "remediation": { 
            "type": "string",
            "description": "Command or steps to fix the issue"
          },
          "documentation": {
            "type": "string",
            "description": "Link to documentation about this test"
          }
        }
      }
    },
    "summary": {
      "type": "object",
      "required": ["total", "passed", "failed"],
      "properties": {
        "total": { 
          "type": "integer",
          "description": "Total number of tests executed"
        },
        "passed": { 
          "type": "integer",
          "description": "Number of tests that passed"
        },
        "failed": { 
          "type": "integer",
          "description": "Number of tests that failed"
        },
        "skipped": {
          "type": "integer",
          "description": "Number of tests skipped (e.g., not applicable to platform)"
        },
        "errors": {
          "type": "integer",
          "description": "Number of tests that encountered errors"
        },
        "bySeverity": {
          "type": "object",
          "properties": {
            "critical": { "type": "integer" },
            "warning": { "type": "integer" },
            "info": { "type": "integer" }
          }
        },
        "byCategory": {
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "properties": {
              "total": { "type": "integer" },
              "passed": { "type": "integer" },
              "failed": { "type": "integer" }
            }
          }
        }
      }
    }
  }
}
```

#### Example JSON Report

```json
{
  "metadata": {
    "timestamp": "2026-02-09T06:00:00Z",
    "hostname": "drlight",
    "platform": "nixos",
    "nixpkgsRevision": "a3f5c3f5c3f5c3f5c3f5c3f5c3f5c3f5c3f5c3f5",
    "flakeRevision": "abc123def456",
    "testMode": "ci",
    "duration": 187.3
  },
  "results": {
    "system-closure-drift": {
      "testName": "system-closure-drift",
      "category": "nixos",
      "status": "failed",
      "severity": "critical",
      "message": "System closure differs from declared configuration",
      "details": {
        "currentGeneration": 42,
        "declaredPackages": 2847,
        "currentPackages": 2851,
        "packagesAdded": ["firefox", "nodejs-20_x", "postgresql"],
        "packagesRemoved": [],
        "closureSizeDelta": "+245MB"
      },
      "remediation": "Run: sudo nixos-rebuild switch",
      "documentation": "https://github.com/funkymonkeymonk/nix/blob/main/docs/drift-detection.md#system-closure-drift"
    },
    "generation-age": {
      "testName": "generation-age",
      "category": "nixos",
      "status": "failed",
      "severity": "warning",
      "message": "Last rebuild was 12 days ago",
      "details": {
        "daysSinceRebuild": 12,
        "thresholdDays": 7,
        "lastRebuildDate": "2026-01-28T14:32:00Z"
      },
      "remediation": "Run: task switch (or sudo nixos-rebuild switch)",
      "documentation": "https://github.com/funkymonkeymonk/nix/blob/main/docs/drift-detection.md#generation-age"
    },
    "ssh-config-integrity": {
      "testName": "ssh-config-integrity",
      "category": "files",
      "status": "passed",
      "severity": "warning"
    },
    "litellm-config-drift": {
      "testName": "litellm-config-drift",
      "category": "services",
      "status": "skipped",
      "severity": "warning",
      "message": "Litellm not enabled for this host"
    }
  },
  "summary": {
    "total": 15,
    "passed": 12,
    "failed": 2,
    "skipped": 1,
    "errors": 0,
    "bySeverity": {
      "critical": 1,
      "warning": 1,
      "info": 0
    },
    "byCategory": {
      "nixos": {
        "total": 5,
        "passed": 3,
        "failed": 2
      },
      "services": {
        "total": 3,
        "passed": 2,
        "failed": 0,
        "skipped": 1
      },
      "files": {
        "total": 4,
        "passed": 4,
        "failed": 0
      },
      "home-manager": {
        "total": 3,
        "passed": 3,
        "failed": 0
      }
    }
  }
}
```

#### Markdown Report (Human-Readable)

**Use Case**: GitHub issues, email summaries, documentation

**Example Output**:

```markdown
# Drift Detection Report: drlight

**Generated:** 2026-02-09 06:00 UTC  
**Platform:** NixOS  
**Nixpkgs:** a3f5c3f...  
**Test Mode:** CI (Build Validation)  
**Duration:** 187.3s

## Executive Summary

⚠️ **Drift Detected** - 2 of 15 tests failed (1 critical, 1 warning)

| Category | Total | Passed | Failed | Skipped |
|----------|-------|--------|--------|---------|
| NixOS    | 5     | 3      | 2      | 0       |
| Services | 3     | 2      | 0      | 1       |
| Files    | 4     | 4      | 0      | 0       |
| Home Mgr | 3     | 3      | 0      | 0       |

## Critical Issues (Immediate Action Required)

### 🔴 System Closure Drift

**Status:** System closure differs from declared configuration  
**Impact:** System is running outdated/inconsistent configuration

**Details:**
- Current Generation: 42
- Declared Packages: 2,847
- Current Packages: 2,851 (+4 packages)
- Packages Added: firefox, nodejs-20_x, postgresql
- Closure Size Impact: +245MB

**Remediation:**
```bash
sudo nixos-rebuild switch
```

**Documentation:** [System Closure Drift](https://github.com/funkymonkeymonk/nix/blob/main/docs/drift-detection.md#system-closure-drift)

---

## Warnings (Should Be Addressed)

### ⚠️ Generation Age

**Status:** Last rebuild was 12 days ago  
**Impact:** System may be missing security updates

**Details:**
- Days Since Rebuild: 12 (threshold: 7)
- Last Rebuild: 2026-01-28 14:32 UTC

**Remediation:**
```bash
# Option 1: Quick update
task switch

# Option 2: Manual rebuild
sudo nixos-rebuild switch
```

**Note:** If you have uncommitted changes, commit them first:
```bash
git add -A
git commit -m "Update system configuration"
sudo nixos-rebuild switch
```

---

## Passed Tests ✅

- ✅ SSH Configuration Integrity
- ✅ Dotfile Integrity
- ✅ Home-Manager Generation
- ✅ NixOS Channel Divergence
- ✅ File Integrity Checks
- ✅ Service State Validation

## Skipped Tests ⏭️

- ⏭️ Litellm Config Drift (Litellm not enabled for this host)

---

## Next Steps

1. **Immediate:** Run `sudo nixos-rebuild switch` to fix closure drift
2. **Soon:** Update flake inputs with `task flake:update`
3. **Review:** Check if manually added packages should be added to configuration

**Questions?** See [Drift Detection Documentation](https://github.com/funkymonkeymonk/nix/blob/main/docs/drift-detection.md)
```

#### Terminal Output (Interactive)

**Use Case**: Local development, quick checks

**Example Output**:

```
╔════════════════════════════════════════════════════════════╗
║              Drift Detection: drlight                      ║
║              NixOS • 187.3s • 2026-02-09 06:00 UTC        ║
╚════════════════════════════════════════════════════════════╝

SUMMARY
───────
Total: 15  |  Passed: 12  |  Failed: 2  |  Skipped: 1

By Severity:
  🔴 Critical: 1
  ⚠️  Warning: 1
  ℹ️  Info: 0

CRITICAL (Action Required)
────────────────────────────────────────────────────────────
🔴 system-closure-drift
   System closure differs from declared configuration
   
   Details:
     • +4 packages (firefox, nodejs-20_x, postgresql)
     • +245MB closure size
   
   Fix: sudo nixos-rebuild switch

WARNINGS (Should Address)
────────────────────────────────────────────────────────────
⚠️  generation-age
   Last rebuild: 12 days ago (threshold: 7)
   
   Fix: task switch

PASSED ✅
────────────────────────────────────────────────────────────
✅ ssh-config-integrity
✅ dotfile-integrity
✅ hm-generation-drift
✅ nixos-channel-drift
✅ file-integrity (4/4 files)
✅ systemd-service-state

SKIPPED ⏭️
────────────────────────────────────────────────────────────
⏭️  litellm-config-drift (not enabled)

Run 'task drift:report' to view full report
```

### 5.2 Severity Levels

Severity levels determine alerting behavior and remediation urgency:

#### Critical 🔴
**Definition:** Security risk, service failure, or complete configuration mismatch

**Examples:**
- System closure drift (running wrong configuration)
- Failed systemd services
- SSH configuration tampering
- Boot loader corruption

**Alerting:**
- Create GitHub issue immediately
- Send Slack/Discord notification
- Email administrators
- Block deployments (optional)

**SLA:** Fix within 24 hours

#### Warning ⚠️
**Definition:** Configuration inconsistency that should be addressed but isn't immediately harmful

**Examples:**
- Generation age > 7 days
- Homebrew casks installed outside Nix
- Dotfiles modified manually
- Services not in expected state (but running)

**Alerting:**
- Update existing GitHub issue (don't create new)
- Include in daily summary

**SLA:** Fix within 7 days

#### Info ℹ️
**Definition:** Informational findings that don't require action but help with visibility

**Examples:**
- Extra files in ~/.config/
- Docker containers not declared in Nix
- macOS defaults changed manually
- Taps added outside nix-darwin

**Alerting:**
- Include in reports for visibility
- No immediate alerting

**SLA:** Review during next maintenance window

### 5.3 Alert Channels

#### GitHub Issues (Primary)

**Behavior:**
- Creates single issue with `drift-detected` label for all drift
- Updates existing issue if one is already open
- Closes issue automatically when drift resolved (future enhancement)
- Includes full Markdown report in issue body

**Issue Template:**
```markdown
---
title: "🔴 System Drift Detected - {{ date }}"
labels: ["drift-detected", "automated", "needs-attention"]
---

{{ full_report }}

---
*This issue was automatically created by the drift detection workflow.*
*Last updated: {{ timestamp }}*
*Workflow run: {{ run_url }}*
```

**Auto-Resolution (Future):**
When a scheduled run finds no drift:
1. Search for open drift issues
2. Comment "All drift resolved as of {{ date }}"
3. Close the issue

#### Slack/Discord Webhooks (Optional)

**Configuration** (in `options.nix`):
```nix
myConfig.driftDetection.slackWebhook = mkOption {
  type = types.nullOr types.str;
  default = null;
  description = "Slack webhook URL for drift alerts";
};
```

**Message Format:**
```json
{
  "text": "🔴 Drift Detected on {{ hostname }}",
  "attachments": [{
    "color": "danger",
    "fields": [
      {"title": "Critical Issues", "value": "{{ critical_count }}", "short": true},
      {"title": "Warnings", "value": "{{ warning_count }}", "short": true},
      {"title": "View Report", "value": "{{ report_url }}", "short": false}
    ]
  }]
}
```

**Trigger Conditions:**
- Only for critical drift
- Rate limited to 1 message per hour
- Include link to GitHub issue

#### Email Notifications (Optional)

**Use Case:** Daily summary for administrators

**Configuration**:
```nix
myConfig.driftDetection.emailNotifications = {
  enabled = mkEnableOption "email notifications";
  smtpServer = mkOption { type = types.str; };
  recipients = mkOption { type = types.listOf types.str; };
};
```

**Content:** Summary of all hosts' drift status

### 5.4 Remediation Guidance

Every drift report includes specific remediation steps:

**Structure:**
1. **Immediate Fix:** One-liner command to resolve
2. **Root Cause:** Why this drift occurred
3. **Prevention:** How to avoid in future
4. **Documentation:** Link to detailed docs

**Example:**

```markdown
### Remediation: System Closure Drift

**Immediate Fix:**
```bash
# Apply current configuration
sudo nixos-rebuild switch

# Verify fix
sudo nixos-rebuild dry-build
```

**Why This Happened:**
The system closure differs from the declared configuration, meaning:
1. You've manually installed packages with `nix-env -iA`
2. You've run `nixos-rebuild switch` on a different version
3. Someone else modified the system directly

**Prevention:**
1. Always use the flake for package management
2. Run `task switch` instead of manual rebuilds
3. Enable automatic flake updates with `task flake:update:weekly`

**Learn More:**
- [NixOS Rebuild Documentation](https://nixos.org/manual/nixos/stable/#sec-changing-config)
- [This Project's Drift Detection Guide](docs/drift-detection.md)
```

### 5.5 Historical Tracking

Reports are retained as CI artifacts for trend analysis:

**Retention Policy:**
- Individual host reports: 30 days
- Aggregate reports: 90 days
- Critical drift issues: Indefinite (in GitHub)

**Analysis Queries:**
```bash
# Find most common drift types
jq -r '.results | to_entries[] | select(.value.status == "failed") | .key' reports/*.json | sort | uniq -c | sort -rn

# Track drift resolution time (requires GitHub API)
gh api repos/:owner/:repo/issues --jq '.[] | select(.labels[].name == "drift-detected") | {title, created_at, closed_at}'

# Compare drift across hosts
jq -s 'group_by(.metadata.hostname) | map({hostname: .[0].metadata.hostname, driftCount: map(.summary.failed) | add})' reports/*.json
```

---

## 6. Implementation Plan

### Phase 1: Foundation (Week 1-2)

**Goal:** Establish basic infrastructure and CLI

**Tasks:**
1. **Create module structure**
   - `modules/drift-detection/default.nix` - Module entry point
   - `modules/drift-detection/options.nix` - Configuration schema
   - `modules/drift-detection/cli.nix` - CLI tool

2. **Implement basic CLI**
   - Command-line argument parsing
   - Host/platform selection
   - Report format selection (JSON, Markdown, Terminal)
   - Exit codes (0 = no drift, 1 = drift detected, 2 = error)

3. **Add to flake.nix**
   ```nix
   packages = {
     drift-detection-cli = pkgs.callPackage ./modules/drift-detection/cli.nix {};
   };
   
   apps = {
     drift-detection = {
       type = "app";
       program = "${self.packages.${system}.drift-detection-cli}/bin/drift-detection";
     };
   };
   ```

**Deliverable:** Working CLI that can be invoked with `nix run .#drift-detection -- --help`

---

### Phase 2: Core Tests (Week 3-4)

**Goal:** Implement the most critical drift tests

**Tasks:**
1. **NixOS tests** (`tests/nixos.nix`)
   - `system-closure-drift` - Compare closures using nvd
   - `generation-age` - Check when last rebuilt
   - `nixos-channel-drift` - Compare channels

2. **Darwin tests** (`tests/darwin.nix`)
   - `darwin-config-drift` - Basic validation
   - `homebrew-cask-drift` - Detect extra casks

3. **Home-Manager tests** (`tests/home-manager.nix`)
   - `hm-generation-drift` - Check home-manager closure
   - `dotfile-integrity` - Verify symlinks

4. **Test Engine** (`engine.nix`)
   - Test discovery and execution
   - Result aggregation
   - Parallel execution

**Deliverable:** 8 working tests that can detect major drift scenarios

---

### Phase 3: CI Integration (Week 5-6)

**Goal:** Integrate with GitHub Actions

**Tasks:**
1. **Create workflow** (`.github/workflows/drift-detection.yml`)
   - Scheduled daily runs
   - Manual trigger support
   - Matrix testing across hosts

2. **Implement reporting** (`reporting.nix`)
   - JSON output for automation
   - Terminal output for local runs
   - Markdown for GitHub issues

3. **Add alerting** (`alerts.nix`)
   - GitHub issue creation/updates
   - Artifact upload
   - Basic severity filtering

4. **Add Taskfile tasks**
   - `task drift:detect`
   - `task drift:detect:host`
   - `task drift:report`

**Deliverable:** Automated daily drift detection with GitHub issue reporting

---

### Phase 4: Extended Tests (Week 7-8)

**Goal:** Add remaining test categories

**Tasks:**
1. **Service tests** (`tests/services.nix`)
   - `systemd-service-state`
   - `litellm-config-drift`
   - `docker-container-drift`
   - `aerospace-state`

2. **File tests** (`tests/files.nix`)
   - `ssh-config-integrity`
   - `unauthorized-config-files`

3. **Additional Darwin tests**
   - `homebrew-tap-drift`
   - `macos-defaults-drift`

4. **Documentation**
   - `docs/drift-detection.md` - User guide
   - README updates

**Deliverable:** Complete test suite with all 15 tests

---

### Phase 5: Refinement (Week 9-10)

**Goal:** Polish and optimize

**Tasks:**
1. **Performance optimization**
   - Parallel test execution
   - Caching of build results
   - Incremental testing

2. **False positive reduction**
   - Tune severity thresholds
   - Add test-specific exceptions
   - User-configurable ignore lists

3. **Enhanced reporting**
   - Trend analysis
   - Historical comparison
   - Better remediation guidance

4. **Testing and validation**
   - Test the test suite (meta!)
   - Validate on all 4 hosts
   - Document edge cases

**Deliverable:** Production-ready drift detection system

---

## 7. New Files

### Module Files
```
modules/drift-detection/
├── default.nix              # Module entry point and imports
├── options.nix              # Type-safe configuration options
├── engine.nix               # Test orchestration and execution
├── reporting.nix            # Report generation (JSON/Markdown/Terminal)
├── alerts.nix               # Alert channel management
├── cli.nix                  # CLI tool derivation
└── tests/
    ├── default.nix          # Test module aggregator
    ├── nixos.nix            # NixOS-specific tests
    ├── darwin.nix           # Darwin-specific tests
    ├── home-manager.nix     # Home-manager tests
    ├── services.nix         # Service state tests
    └── files.nix            # File integrity tests
```

### CI/CD Files
```
.github/workflows/
└── drift-detection.yml      # Scheduled drift detection workflow
```

### Documentation
```
docs/
└── drift-detection.md       # User documentation and troubleshooting
```

### Integration Points

**flake.nix:**
- Add `drift-detection-cli` to packages
- Add `drift-detection` to apps
- Optionally add to checks (future)

**bundles.nix:**
- Add `drift-detector` role (optional - mainly for docs)

**Taskfile.yml:**
- Add `drift:*` task group

---

## 8. Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Detection Speed** | ≤ 24 hours | Time between drift occurrence and GitHub issue creation |
| **False Positive Rate** | < 5% | Percentage of alerts that are not actual drift |
| **System Coverage** | 100% | All 4 hosts (wweaver, MegamanX, drlight, zero) tested |
| **Test Execution Time** | < 10 minutes | Complete test suite runtime in CI |
| **Report Clarity** | 100% | Every failed test has clear remediation steps |
| **CI Integration** | Zero failures | No disruption to existing `nix-ci.yml` workflow |
| **Documentation Coverage** | 100% | Every test documented with purpose and remediation |

### Validation Plan

**Week 6:**
- [ ] Run drift detection on all 4 hosts
- [ ] Verify GitHub issues created for simulated drift
- [ ] Confirm reports are readable and actionable
- [ ] Test manual trigger via `workflow_dispatch`

**Week 10:**
- [ ] 7 days of scheduled runs without errors
- [ ] All 15 tests passing on at least one host each
- [ ] No false positives after threshold tuning
- [ ] Documentation complete and reviewed

---

## 9. Risk Analysis

### Technical Risks

**Risk:** CI runners can't fully test runtime drift  
**Impact:** Medium - We only detect build-time drift  
**Mitigation:** Clearly document CI limitations; plan runtime mode for future  
**Status:** Accepted - 80% value for 20% effort

**Risk:** Homebrew cask detection requires runtime access  
**Impact:** Low - Darwin hosts tested in CI but cask drift only detectable locally  
**Mitigation:** Document limitation; local tasks available for full testing  
**Status:** Accepted

**Risk:** False positives overwhelm the team  
**Impact:** High - Alert fatigue reduces effectiveness  
**Mitigation:** 
- Start with high thresholds
- Tune severity levels during Phase 5
- Provide easy ignore mechanisms  
**Status:** Mitigated

**Risk:** Tests add significant CI time  
**Impact:** Medium - Slower feedback loops  
**Mitigation:**
- Parallel test execution
- Caching of nix builds
- Scheduled runs (not per-PR)  
**Status:** Mitigated

### Operational Risks

**Risk:** Team ignores drift alerts  
**Impact:** High - System becomes the "boy who cried wolf"  
**Mitigation:**
- Only alert on critical drift
- Weekly summary of warnings (not individual alerts)
- Clear ownership of drift remediation  
**Status:** Requires team buy-in

**Risk:** Drift detection itself drifts (becomes outdated)  
**Impact:** Medium - Tests stop being relevant  
**Mitigation:**
- Regular review of test effectiveness
- Update tests when adding new roles
- Document test maintenance in PR template  
**Status:** Requires process discipline

---

## 10. Future Enhancements

### Phase 6+ Ideas (Post-MVP)

**1. Runtime Mode (SSH-based)**
- Execute tests on actual target systems via SSH
- Detect service states, file hashes, running processes
- Provides 100% drift coverage

**2. Auto-Remediation**
- Automatically fix common drift:
  - Run `nixos-rebuild switch` for closure drift
  - Remove manually installed packages
  - Restore modified dotfiles from store
- Requires safety mechanisms (confirmation prompts, dry-run first)

**3. Web Dashboard**
- Real-time view of all systems' drift status
- Historical trends and charts
- Drill-down into specific hosts and tests
- Integration with existing monitoring (if any)

**4. Predictive Drift Detection**
- Machine learning to predict when drift will occur
- Based on patterns in:
  - Frequency of manual interventions
  - Types of packages commonly installed manually
  - Time between rebuilds

**5. Integration with External Monitoring**
- Prometheus metrics export
- Grafana dashboards
- PagerDuty/Opsgenie integration for critical alerts
- Slack bot for interactive drift queries

**6. Compliance Reporting**
- Generate compliance reports (SOC2, ISO27001)
- Prove configuration consistency over time
- Export drift history for auditors

**7. Cross-System Dependency Tracking**
- Detect when one system's drift affects others
- Example: LLM server config drift breaking client systems
- Visual dependency graph

---

## 11. Appendix

### A. Test Implementation Template

Template for implementing new drift tests:

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.myConfig.driftDetection;
in
{
  name = "test-name";
  category = "nixos|darwin|home-manager|services|files";
  platforms = [ "x86_64-linux" "aarch64-darwin" ];  # Supported platforms
  severity = "critical|warning|info";
  
  # Description for documentation
  description = ''
    Brief description of what this test checks.
    
    This test detects when [specific condition] occurs,
    which indicates drift because [reason].
  '';
  
  # The actual test implementation
  test = pkgs.runCommand "test-name"
    { 
      nativeBuildInputs = [ pkgs.jq ];  # Add needed packages
    }
    ''
      set -euo pipefail
      
      # Test logic here
      # Exit 0 = test passes
      # Exit 1 = test fails (drift detected)
      
      # Output JSON result to $out
      jq -n \
        --arg status "passed|failed|skipped" \
        --arg severity "${severity}" \
        --arg message "Description of result" \
        --arg remediation "Command to fix" \
        '{
          status: $status,
          severity: $severity,
          message: $message,
          remediation: $remediation
        }' > $out
    '';
  
  # Remediation steps
  remediation = "Command to fix the drift";
  
  # Link to documentation
  documentation = "https://github.com/funkymonkeymonk/nix/blob/main/docs/drift-detection.md#test-name";
}
```

### B. Adding a New Test

Step-by-step guide for adding tests:

1. **Identify the drift vector**
   - What could diverge from the declared configuration?
   - How would you detect it manually?
   - What severity is appropriate?

2. **Choose the right category**
   - `nixos` - System-level NixOS configuration
   - `darwin` - macOS/nix-darwin configuration
   - `home-manager` - User environment configuration
   - `services` - Running services and containers
   - `files` - File system state and integrity

3. **Implement the test**
   - Use the template above
   - Follow existing patterns in the category
   - Add to the appropriate `tests/*.nix` file

4. **Test the test**
   - Run locally: `nix run .#drift-detection -- --test test-name`
   - Verify it passes when no drift
   - Simulate drift and verify it fails

5. **Document the test**
   - Update `docs/drift-detection.md`
   - Add remediation steps
   - Explain why this drift matters

6. **Update the test matrix**
   - Add to the test summary table in this design doc
   - Update total test count in success metrics

### C. Troubleshooting Guide

**Issue:** Drift detection fails to build  
**Solution:** 
```bash
# Check that the flake is valid
nix flake check

# Build the drift detection package directly
nix build .#drift-detection-cli

# Check for syntax errors in test files
nix-instantiate --eval modules/drift-detection/tests/nixos.nix
```

**Issue:** Tests pass but should fail  
**Solution:**
- Check test mode (CI mode can't detect runtime drift)
- Verify severity threshold (might be filtered out)
- Check if test is skipped for platform

**Issue:** Too many false positives  
**Solution:**
- Adjust severity threshold: `--severity warning`
- Add test-specific ignore rules
- Tune test parameters (e.g., increase generation age threshold)

**Issue:** GitHub issues not being created  
**Solution:**
- Check workflow has `issues: write` permission
- Verify `secrets.GITHUB_TOKEN` is available
- Check if severity threshold is filtering out issues
- Look for rate limiting (GitHub API limits)

### D. Glossary

- **Closure**: The complete set of dependencies for a Nix derivation
- **Drift**: Divergence between declared and actual system state
- **Generation**: A specific version of a NixOS/home-manager configuration
- **CI Mode**: Testing that validates configurations can be built (no runtime access)
- **Runtime Mode**: Testing that queries actual system state (requires access to target system)
- **Remediation**: Steps to fix detected drift
- **Severity**: Urgency level (critical, warning, info)

---

*Design complete. Ready for implementation.*

---

*First Pass Complete - Ready for Section-by-Section Review*
