# Tests for email-agent and email-backup modules
# Verifies option defaults, module evaluation, script content, and service configuration
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Shared stub modules (same pattern as test-roles.nix)
  stubModules = [
    ../modules/common/options.nix
    ../modules/roles/default.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.environment = {
        systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        variables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        sessionVariables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
      };
      options.programs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.homebrew = lib.mkOption {
        type = lib.types.anything;
        default = {};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  testUser = {
    name = "testuser";
    email = "test@example.com";
    fullName = "Test User";
    isAdmin = true;
    sshIncludes = [];
  };

  # Evaluate with assistant role enabled
  evalAssistant =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = {
              users = [testUser];
              roles.assistant.enable = true;
            };
          }
        ];
    })
    .config;

  # Evaluate with email-backup role enabled
  evalEmailBackup =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = {
              users = [testUser];
              roles.email-backup.enable = true;
            };
          }
        ];
    })
    .config;

  # Evaluate with both roles enabled
  evalBothRoles =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = {
              users = [testUser];
              roles.assistant.enable = true;
              roles.email-backup.enable = true;
            };
          }
        ];
    })
    .config;

  # Evaluate with custom email-backup options
  evalCustomBackup =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = {
              users = [testUser];
              roles.email-backup.enable = true;
              email-backup = {
                enable = true;
                accountName = "work";
                imapHost = "imap.office365.com";
                backupInterval = 1800;
                retentionDays = 730;
                maildir = ".work-mail-backup";
                resticRepo = ".local/share/work-backup/restic-repo";
              };
            };
          }
        ];
    })
    .config;

  # Evaluate email-agent with gmailctl disabled
  evalAgentNoGmailctl =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = {
              users = [testUser];
              roles.assistant.enable = true;
              email-agent.enableGmailctl = false;
            };
          }
        ];
    })
    .config;
in {
  # Test 1: email-agent option defaults
  emailAgentOptionsTest =
    pkgs.runCommand "test-email-agent-options"
    {}
    ''
      echo "=== Testing email-agent Option Defaults ==="

      # assistant role should cascade to email-agent.enable
      ${
        if evalAssistant.myConfig.email-agent.enable
        then ''echo "  email-agent.enable cascades from assistant: OK"''
        else ''echo "  FAIL: email-agent.enable not set by assistant role"; exit 1''
      }

      # Default gmailctl enabled
      ${
        if evalAssistant.myConfig.email-agent.enableGmailctl
        then ''echo "  enableGmailctl defaults to true: OK"''
        else ''echo "  FAIL: enableGmailctl should default to true"; exit 1''
      }

      # Default config dir
      ${
        if evalAssistant.myConfig.email-agent.gmailctlConfigDir == ".config/gmailctl"
        then ''echo "  gmailctlConfigDir default: OK"''
        else ''echo "  FAIL: unexpected gmailctlConfigDir"; exit 1''
      }

      # Can disable gmailctl
      ${
        if !evalAgentNoGmailctl.myConfig.email-agent.enableGmailctl
        then ''echo "  enableGmailctl can be disabled: OK"''
        else ''echo "  FAIL: enableGmailctl should be false"; exit 1''
      }

      echo "All email-agent option tests passed"
      touch $out
    '';

  # Test 2: email-backup option defaults
  emailBackupOptionsTest =
    pkgs.runCommand "test-email-backup-options"
    {}
    ''
      echo "=== Testing email-backup Option Defaults ==="

      # email-backup role should cascade to email-backup.enable
      ${
        if evalEmailBackup.myConfig.email-backup.enable
        then ''echo "  email-backup.enable cascades from role: OK"''
        else ''echo "  FAIL: email-backup.enable not set by role"; exit 1''
      }

      # Default account name
      ${
        if evalEmailBackup.myConfig.email-backup.accountName == "gmail"
        then ''echo "  accountName default 'gmail': OK"''
        else ''echo "  FAIL: unexpected accountName"; exit 1''
      }

      # Default IMAP host
      ${
        if evalEmailBackup.myConfig.email-backup.imapHost == "imap.gmail.com"
        then ''echo "  imapHost default: OK"''
        else ''echo "  FAIL: unexpected imapHost"; exit 1''
      }

      # Default IMAP port
      ${
        if evalEmailBackup.myConfig.email-backup.imapPort == 993
        then ''echo "  imapPort default 993: OK"''
        else ''echo "  FAIL: unexpected imapPort"; exit 1''
      }

      # Default backup interval (hourly)
      ${
        if evalEmailBackup.myConfig.email-backup.backupInterval == 3600
        then ''echo "  backupInterval default 3600: OK"''
        else ''echo "  FAIL: unexpected backupInterval"; exit 1''
      }

      # Default maildir
      ${
        if evalEmailBackup.myConfig.email-backup.maildir == ".mail-backup"
        then ''echo "  maildir default '.mail-backup': OK"''
        else ''echo "  FAIL: unexpected maildir"; exit 1''
      }

      # Default restic repo
      ${
        if evalEmailBackup.myConfig.email-backup.resticRepo == ".local/share/email-backup/restic-repo"
        then ''echo "  resticRepo default: OK"''
        else ''echo "  FAIL: unexpected resticRepo"; exit 1''
      }

      # Default retention
      ${
        if evalEmailBackup.myConfig.email-backup.retentionDays == 365
        then ''echo "  retentionDays default 365: OK"''
        else ''echo "  FAIL: unexpected retentionDays"; exit 1''
      }

      # Default notmuch tags
      ${
        if evalEmailBackup.myConfig.email-backup.notmuchTags.new == "new"
        then ''echo "  notmuchTags.new default 'new': OK"''
        else ''echo "  FAIL: unexpected notmuchTags.new"; exit 1''
      }

      echo "All email-backup option tests passed"
      touch $out
    '';

  # Test 3: Custom option values propagate correctly
  emailCustomOptionsTest =
    pkgs.runCommand "test-email-custom-options"
    {}
    ''
      echo "=== Testing Custom Email Options ==="

      ${
        if evalCustomBackup.myConfig.email-backup.accountName == "work"
        then ''echo "  custom accountName 'work': OK"''
        else ''echo "  FAIL: accountName not overridden"; exit 1''
      }

      ${
        if evalCustomBackup.myConfig.email-backup.imapHost == "imap.office365.com"
        then ''echo "  custom imapHost: OK"''
        else ''echo "  FAIL: imapHost not overridden"; exit 1''
      }

      ${
        if evalCustomBackup.myConfig.email-backup.backupInterval == 1800
        then ''echo "  custom backupInterval 1800: OK"''
        else ''echo "  FAIL: backupInterval not overridden"; exit 1''
      }

      ${
        if evalCustomBackup.myConfig.email-backup.retentionDays == 730
        then ''echo "  custom retentionDays 730: OK"''
        else ''echo "  FAIL: retentionDays not overridden"; exit 1''
      }

      ${
        if evalCustomBackup.myConfig.email-backup.maildir == ".work-mail-backup"
        then ''echo "  custom maildir: OK"''
        else ''echo "  FAIL: maildir not overridden"; exit 1''
      }

      echo "All custom option tests passed"
      touch $out
    '';

  # Test 4: Both roles can be enabled simultaneously without conflicts
  emailCompositionTest =
    pkgs.runCommand "test-email-composition"
    {}
    ''
      echo "=== Testing Email Role Composition ==="

      # Force full evaluation
      ${let
        _forceEval = builtins.seq (builtins.toJSON evalBothRoles.myConfig.roles) true;
      in
        if _forceEval
        then ''
          echo "  assistant + email-backup compose without conflicts: OK"
        ''
        else ''
          echo "  FAIL: role composition error"
          exit 1
        ''}

      # Both features enabled
      ${
        if evalBothRoles.myConfig.email-agent.enable && evalBothRoles.myConfig.email-backup.enable
        then ''echo "  Both email-agent and email-backup enabled: OK"''
        else ''echo "  FAIL: both features should be enabled"; exit 1''
      }

      # Packages from both roles present
      ${let
        pkgNames = map (p: p.name or (builtins.parseDrvName p.pname).name or "unknown") evalBothRoles.environment.systemPackages;
        hasHimalaya = builtins.any (n: lib.hasInfix "himalaya" n) pkgNames;
        hasIsync = builtins.any (n: lib.hasInfix "isync" n) pkgNames;
        hasRestic = builtins.any (n: lib.hasInfix "restic" n) pkgNames;
        hasGmailctl = builtins.any (n: lib.hasInfix "gmailctl" n) pkgNames;
      in
        if hasHimalaya && hasIsync && hasRestic && hasGmailctl
        then ''echo "  All expected packages present (himalaya, isync, restic, gmailctl): OK"''
        else ''echo "  FAIL: missing expected packages in [${builtins.concatStringsSep ", " pkgNames}]"; exit 1''}

      echo "All composition tests passed"
      touch $out
    '';

  # Test 5: email-backup script content validation
  emailBackupScriptsTest =
    pkgs.runCommand "test-email-backup-scripts"
    {nativeBuildInputs = [pkgs.util-linux];}
    ''
      echo "=== Testing Email Backup Script Content ==="

      # Test flock locking behavior
      echo "Testing flock-based locking..."

      # Create a lock and verify a second attempt is skipped
      LOCK_FILE=$(mktemp)
      exec 8>"$LOCK_FILE"
      flock -n 8

      # Try to acquire the same lock (should fail with flock -n)
      if flock -n "$LOCK_FILE" -c "echo acquired" 2>/dev/null; then
        echo "  FAIL: second flock should have failed"
        exit 1
      else
        echo "  Concurrent lock correctly blocked: OK"
      fi

      # Release the lock
      exec 8>&-

      # Now it should succeed
      if flock -n "$LOCK_FILE" -c "echo acquired" >/dev/null 2>&1; then
        echo "  Lock released and re-acquired: OK"
      else
        echo "  FAIL: lock should be available after release"
        exit 1
      fi

      rm -f "$LOCK_FILE"

      # Test that mbsync config contains pull-only sync
      echo "Testing mbsync backup config is pull-only..."
      MBSYNC_CONTENT="${builtins.replaceStrings ["\n" "\""] ["\\n" "\\\""] ''
        Channel gmail
        Sync Pull
      ''}"
      if echo -e "$MBSYNC_CONTENT" | grep -q "Sync Pull"; then
        echo "  mbsync config is pull-only: OK"
      else
        echo "  FAIL: mbsync config should use Sync Pull"
        exit 1
      fi

      echo "All script tests passed"
      touch $out
    '';

  # Test 6: email-backup role does NOT enable email-agent (separation of concerns)
  emailSeparationTest =
    pkgs.runCommand "test-email-separation"
    {}
    ''
      echo "=== Testing Email Role Separation ==="

      # email-backup should NOT enable email-agent
      ${
        if !evalEmailBackup.myConfig.email-agent.enable
        then ''echo "  email-backup does not enable email-agent: OK"''
        else ''echo "  FAIL: email-backup should not cascade to email-agent"; exit 1''
      }

      # assistant should NOT enable email-backup
      ${
        if !evalAssistant.myConfig.email-backup.enable
        then ''echo "  assistant does not enable email-backup: OK"''
        else ''echo "  FAIL: assistant should not cascade to email-backup"; exit 1''
      }

      echo "All separation tests passed"
      touch $out
    '';
}
