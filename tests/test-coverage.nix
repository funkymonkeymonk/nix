# Module coverage tracking
# Reports what percentage of modules are exercised by the test suite
{pkgs, ...}: let
  inherit (pkgs) lib;

  # All module files in modules/ (manually enumerated to avoid IFD)
  # Update this list when adding new modules
  allModules = [
    # common/
    "common/cachix.nix"
    "common/core.nix"
    "common/onepassword.nix"
    "common/options.nix"
    "common/shell.nix"
    "common/users.nix"
    # home-manager/
    "home-manager/aliases.nix"
    "home-manager/aerospace.nix"
    "home-manager/charm.nix"
    "home-manager/claude-code.nix"
    "home-manager/default.nix"
    "home-manager/fjj.nix"
    "home-manager/foundation.nix"
    "home-manager/jj-autosync.nix"
    "home-manager/lib.nix"
    "home-manager/opencode.nix"
    "home-manager/pi-coding-agent.nix"
    "home-manager/shell.nix"
    "home-manager/watch-ci-jobs.nix"
    "home-manager/zellij.nix"
    "home-manager/skills/install.nix"
    "home-manager/skills/manifest.nix"
    "home-manager/email-agent.nix"
    "home-manager/email-backup.nix"
    # roles/
    "roles/agent-skills.nix"
    "roles/assistant.nix"
    "roles/claude.nix"
    "roles/creative.nix"
    "roles/default.nix"
    "roles/desktop.nix"
    "roles/developer.nix"
    "roles/email-backup.nix"
    "roles/entertainment.nix"
    "roles/foundation.nix"
    "roles/gaming.nix"
    "roles/llm-host.nix"
    "roles/opencode.nix"
    "roles/pi.nix"
    "roles/workstation.nix"
    # nixos/
    "nixos/base.nix"
    "nixos/desktop.nix"
    "nixos/gaming.nix"
    "nixos/ghostty-terminfo.nix"
    "nixos/streaming.nix"
    # services/
    "services/ollama/common.nix"
    "services/ollama/darwin.nix"
    "services/ollama/nixos.nix"
    "services/openclaw/default.nix"
    "services/vane/common.nix"
    "services/vane/darwin.nix"
    # top-level
    "default.nix"
  ];

  # Modules that are exercised by tests (directly imported or evaluated)
  # This includes modules imported by test stubs via evalModules
  testedModules = [
    # Directly tested via test-packages.nix foundationOptionsTest + configValidationTest
    "common/options.nix"
    # Tested via test-packages.nix onepasswordOptionsTest
    "common/onepassword.nix"
    # Tested via configValidationTest (imports roles/default.nix)
    "roles/default.nix"
    # All role modules tested via test-roles.nix (evalWithRole imports roles/default.nix
    # which imports all role files)
    "roles/agent-skills.nix"
    "roles/claude.nix"
    "roles/creative.nix"
    "roles/desktop.nix"
    "roles/developer.nix"
    "roles/entertainment.nix"
    "roles/foundation.nix"
    "roles/gaming.nix"
    "roles/llm-host.nix"
    "roles/opencode.nix"
    "roles/pi.nix"
    "roles/workstation.nix"
    # Tested via test-email.nix (email-agent and email-backup module tests)
    "roles/assistant.nix"
    "roles/email-backup.nix"
    "home-manager/email-agent.nix"
    "home-manager/email-backup.nix"
    # Tested via VM integration tests (tests/vm/)
    "nixos/base.nix"
    "common/users.nix"
  ];

  # Modules not yet covered by tests
  untestedModules = builtins.filter (m: !(builtins.elem m testedModules)) allModules;

  totalCount = builtins.length allModules;
  testedCount = builtins.length testedModules;
  untestedCount = builtins.length untestedModules;

  # Integer percentage (avoid floating point in Nix)
  coveragePct = (testedCount * 100) / totalCount;
in {
  moduleCoverageTest =
    pkgs.runCommand "test-module-coverage"
    {}
    ''
      echo "=== Module Test Coverage Report ==="
      echo ""
      echo "Total modules:    ${toString totalCount}"
      echo "Tested modules:   ${toString testedCount}"
      echo "Untested modules: ${toString untestedCount}"
      echo "Coverage:         ${toString coveragePct}%"
      echo ""
      echo "--- Tested Modules ---"
      ${lib.concatMapStringsSep "\n" (m: ''echo "  [x] ${m}"'') testedModules}
      echo ""
      echo "--- Untested Modules ---"
      ${lib.concatMapStringsSep "\n" (m: ''echo "  [ ] ${m}"'') untestedModules}
      echo ""

      # Write coverage data for CI consumption
      mkdir -p $out
      echo '${builtins.toJSON {
        total = totalCount;
        tested = testedCount;
        untested = untestedCount;
        percentage = coveragePct;
        untestedList = untestedModules;
      }}' > $out/coverage.json

      echo "Coverage report written to $out/coverage.json"
    '';
}
