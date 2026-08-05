{pkgs, lib, ...}: let
  usersNixPath = builtins.toString ./../modules/common/users.nix;
  usersNixContent = builtins.readFile usersNixPath;
in {
  # Simple test to verify programs.git.enable is set in users.nix
  gitEnableSimpleTest =
    if builtins.match ".*programs\.git.*enable.*=.*true.*" usersNixContent != null
    then pkgs.runCommand "test-git-enable-simple" {} "echo 'programs.git.enable = true: OK' && touch $out"
    else builtins.throw "FAIL: programs.git.enable = true not found in users.nix";

  # Test that git settings exist
  gitSettingsExistTest =
    if builtins.match ".*programs\.git\.settings.*" usersNixContent != null
    then pkgs.runCommand "test-git-settings-exist" {} "echo 'programs.git.settings found: OK' && touch $out"
    else builtins.throw "FAIL: programs.git.settings not found";

  # Test that commit.gpgsign is configured
  gitCommitSigningExistsTest =
    if builtins.match ".*commit\.gpgsign.*" usersNixContent != null
    then pkgs.runCommand "test-git-commit-signing-exists" {} "echo 'commit.gpgsign configuration found: OK' && touch $out"
    else builtins.throw "FAIL: commit.gpgsign not found";

  gitConfigGenerationTest =
    if builtins.match ".*home\.file.*" usersNixContent != null
    then pkgs.runCommand "test-git-config-generation" {} "echo 'home.file configuration found: OK' && touch $out"
    else builtins.throw "FAIL: home.file not found";

  gitUserConfigTest =
    if builtins.match ".*user\.name.*user\.email.*" usersNixContent != null
    then pkgs.runCommand "test-git-user-config" {} "echo 'user.name/email configuration found: OK' && touch $out"
    else builtins.throw "FAIL: user.name/email not found";
}
