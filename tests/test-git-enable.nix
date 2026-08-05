{pkgs, ...}: {
  # Simple test to verify programs.git.enable is set in users.nix
  gitEnableSimpleTest =
    pkgs.runCommand "test-git-enable-simple"
    {}
    ''
      echo "=== Testing programs.git.enable in users.nix ==="

      # Read the users.nix file and check for programs.git.enable = true
      if grep -q "programs\.git\.enable = true" ${../modules/common/users.nix}; then
        echo "  programs.git.enable = true: OK"
        touch $out
      else
        echo "  FAIL: programs.git.enable = true not found in users.nix"
        exit 1
      fi
    '';

  # Test that git settings exist
  gitSettingsExistTest =
    pkgs.runCommand "test-git-settings-exist"
    {}
    ''
      echo "=== Testing programs.git.settings in users.nix ==="

      if grep -q "programs\.git\.settings" ${../modules/common/users.nix}; then
        echo "  programs.git.settings found: OK"
        touch $out
      else
        echo "  FAIL: programs.git.settings not found"
        exit 1
      fi
    '';

  # Test that commit.gpgsign is configured
  gitCommitSigningExistsTest =
    pkgs.runCommand "test-git-commit-signing-exists"
    {}
    ''
      echo "=== Testing commit.gpgsign in users.nix ==="

      if grep -q "commit\.gpgsign" ${../modules/common/users.nix}; then
        echo "  commit.gpgsign configuration found: OK"
        touch $out
      else
        echo "  FAIL: commit.gpgsign not found"
        exit 1
      fi
    '';

  gitConfigGenerationTest =
    pkgs.runCommand "test-git-config-generation"
    {}
    ''
      echo "=== Testing .gitconfig reference in users.nix ==="

      if grep -q "home\.file" ${../modules/common/users.nix}; then
        echo "  home.file configuration found: OK"
        touch $out
      else
        echo "  FAIL: home.file not found"
        exit 1
      fi
    '';

  gitUserConfigTest =
    pkgs.runCommand "test-git-user-config"
    {}
    ''
      echo "=== Testing Git user config in users.nix ==="

      if grep -q "user\.name\|user\.email" ${../modules/common/users.nix}; then
        echo "  user.name/email configuration found: OK"
        touch $out
      else
        echo "  FAIL: user.name/email not found"
        exit 1
      fi
    '';
}
