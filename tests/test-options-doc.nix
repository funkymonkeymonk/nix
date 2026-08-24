# Tests for scripts/generate-options-doc.nix — the generator behind
# docs/reference/options.md.
#
# 1. optionsDocKnownOption: a golden-option regression test asserting a
#    well-known myConfig option (myConfig.roles.developer.enable) shows up
#    in the generated markdown with the correct type/default. This is the
#    TDD anchor for the generator itself: write this test first, watch it
#    fail with no generator, then implement.
# 2. optionsDocSubmoduleRecursion: asserts a submodule-nested option
#    (myConfig.users.*.name) is documented, proving recursion into
#    submodules works.
# 3. optionsDocFresh: regenerates the markdown and diffs it byte-for-byte
#    against the checked-in docs/reference/options.md. Fails CI if someone
#    changes a myConfig option without re-running
#    `devenv tasks run docs:generate-options`.
{
  pkgs,
  self,
  ...
}: let
  inherit (pkgs) lib;
  optionsDoc = import ../scripts/generate-options-doc.nix {inherit lib self;};
in {
  optionsDocKnownOptionTest =
    pkgs.runCommand "test-options-doc-known-option"
    {
      passAsFile = ["markdown"];
      markdown = optionsDoc.markdown;
    }
    ''
      echo "=== Testing generated options doc contains a known option ==="

      if ! grep -qE '\| `developer\.enable` \| boolean \|' "$markdownPath"; then
        echo "FAIL: myConfig.roles.developer.enable missing from generated doc"
        echo "--- generated doc (roles section) ---"
        grep -A 20 '### myConfig.roles' "$markdownPath" || true
        exit 1
      fi
      echo "  myConfig.roles.developer.enable present with boolean type: OK"

      touch $out
    '';

  optionsDocSubmoduleRecursionTest =
    pkgs.runCommand "test-options-doc-submodule-recursion"
    {
      passAsFile = ["markdown"];
      markdown = optionsDoc.markdown;
    }
    ''
      echo "=== Testing generated options doc recurses into submodules ==="

      if ! grep -qE '\| `\*\.name` \|' "$markdownPath"; then
        echo "FAIL: myConfig.users.*.name (submodule-nested option) missing from generated doc"
        echo "--- generated doc (users section) ---"
        grep -A 10 '### myConfig.users' "$markdownPath" || true
        exit 1
      fi
      echo "  myConfig.users.*.name present: OK"

      touch $out
    '';

  optionsDocFreshTest =
    pkgs.runCommand "test-options-doc-fresh"
    {
      passAsFile = ["generated"];
      generated = optionsDoc.markdown;
      checkedIn = ../docs/reference/options.md;
    }
    ''
      echo "=== Checking docs/reference/options.md is up to date ==="

      if diff -u "$checkedIn" "$generatedPath" > $TMPDIR/diff.txt 2>&1; then
        echo "OK: docs/reference/options.md matches the generator output"
      else
        echo "FAIL: docs/reference/options.md is stale."
        echo ""
        cat $TMPDIR/diff.txt
        echo ""
        echo "Run: devenv tasks run docs:generate-options"
        exit 1
      fi

      touch $out
    '';
}
