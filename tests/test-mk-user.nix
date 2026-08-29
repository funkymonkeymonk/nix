# Unit tests for library/lib/mk-user.nix
#
# mkUser was extracted verbatim from flake.nix's inline `outputs`
# let-binding so that both flake.nix and the upcoming
# library/machines/zero.nix flake-parts module (which cannot reach
# into flake.nix's local let-block) can import the same helper with
# identical behavior. These tests pin the exact output shape and the
# curried `name: email: {...}` calling convention so a future edit
# can't silently change either.
{pkgs, ...}: let
  mkUser = import ../library/lib/mk-user.nix;
  result = mkUser "monkey" "me@willweaver.dev";
  expected = {
    users = [
      {
        name = "monkey";
        email = "me@willweaver.dev";
        fullName = "Will Weaver";
        isAdmin = true;
        sshIncludes = [];
      }
    ];
    onepassword.enable = true;
    opencode = {
      enable = true;
      model = "local-bifrost/vllm-mlx-qwen/qwen3.8-27b";
    };
    claude-code = {
      enable = false;
    };
    llmClient.rtk.enable = true;
  };
in {
  mkUserTest =
    pkgs.runCommand "test-mk-user"
    {}
    ''
      echo "=== Testing mkUser ==="

      ${
        if result == expected
        then ''echo "  mkUser \"monkey\" \"me@willweaver.dev\" matches expected structure: OK"''
        else ''echo "  FAIL: mkUser output does not match expected structure"; exit 1''
      }

      ${
        if (builtins.elemAt result.users 0).name == "monkey"
        then ''echo "  users[0].name = monkey: OK"''
        else ''echo "  FAIL: users[0].name should be monkey"; exit 1''
      }

      ${
        if (builtins.elemAt result.users 0).email == "me@willweaver.dev"
        then ''echo "  users[0].email = me@willweaver.dev: OK"''
        else ''echo "  FAIL: users[0].email should be me@willweaver.dev"; exit 1''
      }

      ${
        if (builtins.elemAt result.users 0).fullName == "Will Weaver"
        then ''echo "  users[0].fullName = Will Weaver: OK"''
        else ''echo "  FAIL: users[0].fullName should be 'Will Weaver'"; exit 1''
      }

      ${
        if (builtins.elemAt result.users 0).isAdmin == true
        then ''echo "  users[0].isAdmin = true: OK"''
        else ''echo "  FAIL: users[0].isAdmin should be true"; exit 1''
      }

      ${
        if (builtins.elemAt result.users 0).sshIncludes == []
        then ''echo "  users[0].sshIncludes = []: OK"''
        else ''echo "  FAIL: users[0].sshIncludes should be []"; exit 1''
      }

      ${
        if result.onepassword.enable == true
        then ''echo "  onepassword.enable = true: OK"''
        else ''echo "  FAIL: onepassword.enable should be true"; exit 1''
      }

      ${
        if result.opencode.enable == true
        then ''echo "  opencode.enable = true: OK"''
        else ''echo "  FAIL: opencode.enable should be true"; exit 1''
      }

      ${
        if result.opencode.model == "local-bifrost/vllm-mlx-qwen/qwen3.8-27b"
        then ''echo "  opencode.model = managed Qwen: OK"''
        else ''echo "  FAIL: opencode.model should be the managed Qwen model"; exit 1''
      }

      ${
        if result.claude-code.enable == false
        then ''echo "  claude-code.enable = false: OK"''
        else ''echo "  FAIL: claude-code.enable should be false"; exit 1''
      }

      ${
        if result.llmClient.rtk.enable == true
        then ''echo "  llmClient.rtk.enable = true: OK"''
        else ''echo "  FAIL: llmClient.rtk.enable should be true"; exit 1''
      }

      echo "All mkUser tests passed"
      touch $out
    '';

  mkUserCallingConventionTest =
    pkgs.runCommand "test-mk-user-calling-convention"
    {}
    ''
      echo "=== Testing mkUser calling convention (name: email: {...}) ==="

      ${
        if builtins.isFunction mkUser
        then ''echo "  mkUser is a function: OK"''
        else ''echo "  FAIL: mkUser should be a function"; exit 1''
      }

      ${
        if builtins.isFunction (mkUser "onlyname")
        then ''echo "  mkUser applied to a single arg returns another function (curried name: email: {...}): OK"''
        else ''echo "  FAIL: mkUser should be curried as name: email: {...}, not {}: name: email: {...}"; exit 1''
      }

      echo "All mkUser calling convention tests passed"
      touch $out
    '';
}
