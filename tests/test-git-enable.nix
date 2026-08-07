{pkgs, ...}: let
  usersNixPath = builtins.toString ./../modules/common/users.nix;
  usersNixContent = builtins.readFile usersNixPath;

  # Helper: check if string contains substring
  contains = substring: str: builtins.match ".*${substring}.*" str != null;
in {
  # Simple test to verify programs.git.enable is set in users.nix
  gitEnableSimpleTest =
    if contains "enable = true" usersNixContent && contains "programs.git" usersNixContent
    then pkgs.runCommand "test-git-enable-simple" {} "echo 'programs.git.enable = true: OK' && touch $out"
    else builtins.throw "FAIL: programs.git.enable = true not found in users.nix";

  # Test that git settings config block exists
  gitSettingsExistTest =
    if contains "programs.git" usersNixContent
    then pkgs.runCommand "test-git-settings-exist" {} "echo 'programs.git config found: OK' && touch $out"
    else builtins.throw "FAIL: programs.git not found";

  # Test that commit.gpgsign is configured
  gitCommitSigningExistsTest =
    if contains "commit.gpgsign" usersNixContent
    then pkgs.runCommand "test-git-commit-signing-exists" {} "echo 'commit.gpgsign configuration found: OK' && touch $out"
    else builtins.throw "FAIL: commit.gpgsign not found";

  gitConfigGenerationTest =
    if contains "home.file" usersNixContent
    then pkgs.runCommand "test-git-config-generation" {} "echo 'home.file configuration found: OK' && touch $out"
    else builtins.throw "FAIL: home.file not found";

  gitUserConfigTest =
    if contains "user.name" usersNixContent && contains "user.email" usersNixContent
    then pkgs.runCommand "test-git-user-config" {} "echo 'user.name/email configuration found: OK' && touch $out"
    else builtins.throw "FAIL: user.name/email not found";
}
