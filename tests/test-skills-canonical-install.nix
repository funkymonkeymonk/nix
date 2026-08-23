# Canonical skill install location tests (~/.agents/skills/<name>)
#
# Verifies the agentskills.io-convention unification: skills resolved by
# hmLib.mkFullSkillDirs are installed ONCE, under ~/.agents/skills/<name>,
# via the new modules/home-manager/skills/canonical-install.nix module —
# gated on "any skill-consuming role enabled" (skills.enabledRoles != []),
# not on any single agent's role.enable.
#
# Also verifies opencode.nix and pi-coding-agent.nix no longer duplicate
# those same skill directories under their own per-agent paths
# (.config/opencode/skills/<name> and .pi/agent/skills/<name>), while
# preserving opencode's auto-loaded digest and bundled skill commands.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};
  hmLib = import ../modules/home-manager/lib.nix {inherit lib;};

  # ── Fabricate a minimal osConfig ────────────────────────────────────────
  # Real option defaults come from evaluating options.nix + onepassword.nix
  # (same modules production hosts compose), then we override the specific
  # fields each home-manager module under test reads.
  osConfigBaseModules = stubs.base ++ stubs.onepassword;

  mkOsConfig = overrides:
    (lib.evalModules {
      modules = osConfigBaseModules ++ [{config.myConfig = overrides;}];
    }).config;

  # osConfig with two skill-consuming roles enabled (opencode + pi), used to
  # exercise the "install everywhere it's needed, once" happy path.
  osConfigWithSkills = mkOsConfig {
    skills.enabledRoles = ["opencode" "pi"];
    opencode.enable = true;
    pi.enable = true;
  };

  # osConfig with no skill-consuming roles enabled at all — the gate for
  # canonical-install.nix must produce zero home.file entries.
  osConfigNoSkills = mkOsConfig {
    skills.enabledRoles = [];
  };

  # ── Home-manager module option stubs ────────────────────────────────────
  # Minimal stand-ins for the real home.* / programs.* options so the real
  # module files under test (canonical-install.nix, opencode.nix,
  # pi-coding-agent.nix) can be evaluated directly via evalModules, with
  # osConfig injected the same way home-manager's nix-darwin/NixOS glue
  # injects it in production.
  homeManagerOptionStubs = {
    options.home = {
      file = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      sessionVariables = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      activation = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    };
    options.programs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };

  mkHomeManagerEval = {
    osConfig,
    module,
  }:
    (lib.evalModules {
      modules = [
        homeManagerOptionStubs
        {
          config._module.args = {inherit pkgs osConfig;};
        }
        module
      ];
    }).config;

  # canonical-install.nix evaluated with skills enabled / disabled
  canonicalWithSkills = mkHomeManagerEval {
    osConfig = osConfigWithSkills;
    module = ../modules/home-manager/skills/canonical-install.nix;
  };
  canonicalNoSkills = mkHomeManagerEval {
    osConfig = osConfigNoSkills;
    module = ../modules/home-manager/skills/canonical-install.nix;
  };

  # opencode.nix / pi-coding-agent.nix evaluated with skills enabled
  opencodeHm = mkHomeManagerEval {
    osConfig = osConfigWithSkills;
    module = ../modules/home-manager/opencode.nix;
  };
  piHm = mkHomeManagerEval {
    osConfig = osConfigWithSkills;
    module = ../modules/home-manager/pi-coding-agent.nix;
  };

  # The skills opencode/pi roles actually resolve to, for cross-checking
  # against canonical-install.nix's output (same helper, same enabledRoles).
  resolvedSkillNames =
    builtins.attrNames
    (
      hmLib.mkFullSkillDirs {enabledRoles = ["opencode" "pi"];}
    ).skillDirs;

  homeFileKeys = evaluated: builtins.attrNames evaluated.home.file;

  hasPrefix = prefix: s: lib.hasPrefix prefix s;

  # AGENT_SKILLS_PATH (roles/agent-skills.nix) must point at the new
  # canonical location too, or `skills-status`/`skills-list` shell aliases
  # would point at a directory that no longer exists.
  evalAgentSkills =
    (lib.evalModules {
      modules =
        stubs.agentSkills
        ++ [
          {
            config.myConfig.roles.agent-skills.enable = true;
          }
        ];
    }).config;
in {
  # New canonical-install.nix writes ~/.agents/skills/<name> for every skill
  # resolved by mkFullSkillDirs, when any skill-consuming role is enabled.
  canonicalInstallWritesAgentsSkillsTest =
    pkgs.runCommand "test-canonical-install-writes-agents-skills"
    {}
    ''
      echo "=== Testing canonical-install.nix writes ~/.agents/skills/<name> ==="

      echo "  Resolved skill count: ${toString (builtins.length resolvedSkillNames)}"
      ${
        if builtins.length resolvedSkillNames > 0
        then ''echo "  At least one skill resolved for [opencode, pi]: OK"''
        else ''echo "  Expected at least one skill for [opencode, pi]!"; exit 1''
      }

      ${lib.concatMapStringsSep "\n" (name: ''
          ${
            if builtins.hasAttr ".agents/skills/${name}" canonicalWithSkills.home.file
            then ''echo "  .agents/skills/${name} present: OK"''
            else ''
              echo "  .agents/skills/${name} MISSING from canonical-install.nix output!"
              exit 1
            ''
          }
        '')
        resolvedSkillNames}

      echo "  Total .agents/skills/ entries: ${toString (builtins.length (homeFileKeys canonicalWithSkills))}"
      ${
        if builtins.length (homeFileKeys canonicalWithSkills) == builtins.length resolvedSkillNames
        then ''echo "  canonical-install.nix writes exactly the resolved skill set: OK"''
        else ''
          echo "  canonical-install.nix wrote a different count than resolved skills!"
          exit 1
        ''
      }

      echo "canonical-install.nix installs the full skill set under ~/.agents/skills/"
      touch $out
    '';

  # Gated on skills.enabledRoles != [] — not on any single agent's role.enable.
  canonicalInstallGatedOnEmptyRolesTest =
    pkgs.runCommand "test-canonical-install-gated-on-empty-roles"
    {}
    ''
      echo "=== Testing canonical-install.nix gating ==="

      ${
        if canonicalNoSkills.home.file == {}
        then ''echo "  No skill-consuming roles enabled -> zero home.file entries: OK"''
        else ''
          echo "  Expected zero home.file entries when enabledRoles == [], got: ${builtins.toJSON (homeFileKeys canonicalNoSkills)}"
          exit 1
        ''
      }

      echo "canonical-install.nix correctly gates on enabledRoles != []"
      touch $out
    '';

  # opencode.nix no longer writes its own copies of internal/superpowers
  # skill directories under .config/opencode/skills/<name> — only the
  # auto-loaded digest file remains there (a distinct opencode-only
  # feature, unrelated to skill directory discovery).
  opencodeNoLongerWritesOwnSkillDirsTest =
    pkgs.runCommand "test-opencode-no-longer-writes-own-skill-dirs"
    {}
    ''
      echo "=== Testing opencode.nix no longer duplicates skill directories ==="

      ${
        if (opencodeHm.programs.opencode.skills or {}) == {}
        then ''echo "  programs.opencode.skills == {} (or unset, real module default): OK"''
        else ''
          echo "  programs.opencode.skills should be empty, got: ${builtins.toJSON opencodeHm.programs.opencode.skills}"
          exit 1
        ''
      }

      ${lib.concatMapStringsSep "\n" (name: ''
          ${
            if !(builtins.hasAttr ".config/opencode/skills/${name}" opencodeHm.home.file)
            then ''echo "  .config/opencode/skills/${name} absent: OK"''
            else ''
              echo "  .config/opencode/skills/${name} should NOT be written by opencode.nix anymore!"
              exit 1
            ''
          }
        '')
        resolvedSkillNames}

      # The auto-loaded digest is a distinct opencode feature and must survive.
      ${
        if builtins.hasAttr ".config/opencode/skills/auto-loaded.md" opencodeHm.home.file
        then ''echo "  auto-loaded.md digest preserved: OK"''
        else ''
          echo "  auto-loaded.md digest should still be written by opencode.nix!"
          exit 1
        ''
      }

      echo "opencode.nix delegates skill directory installation to canonical-install.nix"
      touch $out
    '';

  # Skill-bundled commands (e.g. jj's /finish /pr /push, yak-shaving's
  # /shave) are independent of skill DIRECTORY placement — confirm they
  # keep working unchanged after the move.
  opencodeSkillCommandsStillWorkTest =
    pkgs.runCommand "test-opencode-skill-commands-still-work"
    {}
    ''
      echo "=== Testing opencode.nix skill-bundled commands survive the move ==="

      ${
        if builtins.hasAttr "shave" opencodeHm.programs.opencode.commands
        then ''echo "  /shave command still wired: OK"''
        else ''
          echo "  /shave command should still be wired via programs.opencode.commands!"
          exit 1
        ''
      }

      echo "Skill-bundled commands are unaffected by the skill directory move"
      touch $out
    '';

  # pi-coding-agent.nix no longer writes .pi/agent/skills/<name> entries for
  # manifest (internal/superpowers) skills at all.
  piNoLongerWritesManifestSkillDirsTest =
    pkgs.runCommand "test-pi-no-longer-writes-manifest-skill-dirs"
    {}
    ''
      echo "=== Testing pi-coding-agent.nix no longer duplicates skill directories ==="

      ${
        let
          piSkillFileKeys = builtins.filter (hasPrefix ".pi/agent/skills/") (homeFileKeys piHm);
        in
          if piSkillFileKeys == []
          then ''echo "  No .pi/agent/skills/<name> entries written: OK"''
          else ''
            echo "  pi-coding-agent.nix should not write .pi/agent/skills/<name> entries, found: ${builtins.toJSON piSkillFileKeys}"
            exit 1
          ''
      }

      echo "pi-coding-agent.nix delegates skill directory installation to canonical-install.nix"
      touch $out
    '';

  # AGENT_SKILLS_PATH must follow the skill directories to their new home,
  # or skills-status/skills-list shell aliases silently point at nothing.
  agentSkillsPathPointsAtCanonicalLocationTest =
    pkgs.runCommand "test-agent-skills-path-points-at-canonical-location"
    {}
    ''
      echo "=== Testing AGENT_SKILLS_PATH points at ~/.agents/skills ==="

      ${
        if evalAgentSkills.environment.variables.AGENT_SKILLS_PATH == "$HOME/.agents/skills"
        then ''echo "  AGENT_SKILLS_PATH = \$HOME/.agents/skills: OK"''
        else ''
          echo "  AGENT_SKILLS_PATH should be \$HOME/.agents/skills, got: ${evalAgentSkills.environment.variables.AGENT_SKILLS_PATH}"
          exit 1
        ''
      }

      echo "AGENT_SKILLS_PATH follows the canonical skill install location"
      touch $out
    '';
}
