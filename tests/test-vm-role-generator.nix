# Tests for the generic per-role VM package test generator (mkRoleVmTest).
#
# tests/vm/default.nix is only ever *imported* by tests/default.nix when
# `pkgs.stdenv.hostPlatform.isLinux` (VM tests use pkgs.testers.nixosTest,
# which requires a Linux guest). To validate mkRoleVmTest from any host
# platform (including this repo's aarch64-darwin dev machines), we build our
# own x86_64-linux `pkgs` here -- mirroring exactly how flake.nix constructs
# pkgs for the real `checks.x86_64-linux.*` outputs -- and import
# tests/vm/default.nix directly with it.
#
# This is pure evaluation (lib.evalModules under the hood via
# pkgs.testers.nixosTest): no VM is booted, no Linux builder is required.
# `nodes.machine` on a nixosTest derivation exposes the fully evaluated
# NixOS config for that node (see nixos/lib/testing/nodes.nix passthru.nodes),
# so we can inspect `environment.systemPackages` and `config.testScript`
# without building anything.
{
  pkgs,
  self,
  ...
}: let
  lib = pkgs.lib;
  inputs = self.inputs;

  # Same construction as flake.nix's `checks` output, pinned to
  # x86_64-linux (the only system VM tests are ever exposed under).
  linuxPkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
    overlays = [(import ../overlays {inherit inputs;})];
  };

  vmTests = import ./vm {pkgs = linuxPkgs;};

  # Raw source for structural assertions that shouldn't require forcing a
  # full NixOS module evaluation (e.g. presence-only-check style, single
  # source of truth for the module list).
  vmSource = builtins.readFile ./vm/default.nix;

  hasGenerator = lib.hasInfix "mkRoleVmTest" vmSource;
  usesCommandV = lib.hasInfix "command -v" vmSource;
  noVersionExec = !(lib.hasInfix "--version" vmSource);
  declaresFoundationCheck = lib.hasInfix ''vm-role-foundation = mkRoleVmTest "foundation"'' vmSource;
  declaresDeveloperCheck = lib.hasInfix ''vm-role-developer = mkRoleVmTest "developer"'' vmSource;

  # "Single source of truth" guard: the shared module list (identified by
  # a distinctive path only mkTest's module list should contain) must
  # appear exactly once in the file. If mkRoleVmTest grew its own parallel
  # copy of the module list, this path would appear twice.
  moduleListMarker = "../../modules/roles/default.nix";
  moduleListOccurrences =
    builtins.length (builtins.filter (s: s != "") (
      lib.splitString moduleListMarker vmSource
    ))
    - 1;

  hasFoundationAttr = builtins.hasAttr "vm-role-foundation" vmTests;
  hasDeveloperAttr = builtins.hasAttr "vm-role-developer" vmTests;

  # Binary names each role's VM test is expected to presence-check, derived
  # the same way mkRoleVmTest does: pkg.meta.mainProgram or pkg.pname or
  # pkg.name. Verified against this repo's real overlay-enabled nixpkgs.
  expectedBinaries = {
    foundation = ["hx" "jj" "rg" "gh" "jq" "delta"];
    developer = ["clang" "node" "yarn" "yx"];
  };

  # Check a role's generated test: the role must be enabled on the node,
  # the shared node modules (proving module-list reuse) must be present,
  # every expected binary must be resolvable from environment.systemPackages
  # using the mainProgram/pname/name formula, and the rendered testScript
  # must presence-check each binary via `command -v` (never `--version`).
  checkRole = role: let
    testAttr = "vm-role-${role}";
    hasAttrForRole = builtins.hasAttr testAttr vmTests;
  in
    if !hasAttrForRole
    then ''
      echo "  ${testAttr}: NOT FOUND in tests/vm/default.nix output"
      exit 1
    ''
    else let
      node = vmTests.${testAttr}.nodes.machine;
      roleEnabled = node.myConfig.roles.${role}.enable or false;
      sharesModules = builtins.hasAttr "testuser" node.users.users;
      actualBinaries = map (pkg: pkg.meta.mainProgram or pkg.pname or pkg.name) node.environment.systemPackages;
      expected = expectedBinaries.${role};
      missingBinaries = builtins.filter (b: !(builtins.elem b actualBinaries)) expected;
      script = vmTests.${testAttr}.config.testScript;
      scriptChecksBinary = b: lib.hasInfix "command -v ${b}" script || lib.hasInfix "command -v '${b}'" script;
      missingFromScript = builtins.filter (b: !(scriptChecksBinary b)) expected;
    in ''
      ${
        if roleEnabled
        then "echo \"  ${testAttr}: myConfig.roles.${role}.enable = true: OK\""
        else ''
          echo "  ${testAttr}: role was not enabled on the test node"
          exit 1
        ''
      }
      ${
        if sharesModules
        then "echo \"  ${testAttr}: shares mkTest's node modules (testuser present): OK\""
        else ''
          echo "  ${testAttr}: test node is missing testuser -- does it reuse mkTest's module list?"
          exit 1
        ''
      }
      ${
        if missingBinaries == []
        then "echo \"  ${testAttr}: all expected binaries resolved (${builtins.concatStringsSep ", " expected}): OK\""
        else ''
          echo "  ${testAttr}: MISSING binaries in environment.systemPackages: ${builtins.concatStringsSep ", " missingBinaries}"
          echo "  actual: ${builtins.concatStringsSep ", " actualBinaries}"
          exit 1
        ''
      }
      ${
        if missingFromScript == []
        then "echo \"  ${testAttr}: testScript presence-checks all expected binaries: OK\""
        else ''
          echo "  ${testAttr}: testScript missing 'command -v' checks for: ${builtins.concatStringsSep ", " missingFromScript}"
          exit 1
        ''
      }
    '';

  script = ''
    echo "=== Testing mkRoleVmTest generator structure ==="
    ${
      if hasGenerator
      then ''echo "  mkRoleVmTest defined in tests/vm/default.nix: OK"''
      else ''
        echo "  mkRoleVmTest NOT found in tests/vm/default.nix"
        exit 1
      ''
    }
    ${
      if usesCommandV
      then ''echo "  uses 'command -v' presence checks: OK"''
      else ''
        echo "  'command -v' not found -- generator must use presence-only checks"
        exit 1
      ''
    }
    ${
      if noVersionExec
      then ''echo "  never execs '--version' (avoids GUI/Electron hang risk): OK"''
      else ''
        echo "  found '--version' in tests/vm/default.nix -- must use presence-only checks"
        exit 1
      ''
    }
    ${
      if declaresFoundationCheck
      then ''echo "  vm-role-foundation = mkRoleVmTest \"foundation\": OK"''
      else ''
        echo "  vm-role-foundation = mkRoleVmTest \"foundation\" not found"
        exit 1
      ''
    }
    ${
      if declaresDeveloperCheck
      then ''echo "  vm-role-developer = mkRoleVmTest \"developer\": OK"''
      else ''
        echo "  vm-role-developer = mkRoleVmTest \"developer\" not found"
        exit 1
      ''
    }
    ${
      if moduleListOccurrences == 1
      then ''echo "  single source of truth for the node module list: OK"''
      else ''
        echo "  expected the shared module list marker (${moduleListMarker}) exactly once, found ${toString moduleListOccurrences} -- mkRoleVmTest must not carry a parallel module list"
        exit 1
      ''
    }
    echo ""
    echo "=== Testing vm-role-foundation and vm-role-developer are exported ==="
    ${
      if hasFoundationAttr
      then ''echo "  vm-role-foundation exported from tests/vm/default.nix: OK"''
      else ''
        echo "  vm-role-foundation NOT exported from tests/vm/default.nix"
        exit 1
      ''
    }
    ${
      if hasDeveloperAttr
      then ''echo "  vm-role-developer exported from tests/vm/default.nix: OK"''
      else ''
        echo "  vm-role-developer NOT exported from tests/vm/default.nix"
        exit 1
      ''
    }
    echo ""
    echo "=== Testing per-role binary resolution and testScript content ==="
    ${checkRole "foundation"}
    ${checkRole "developer"}
    echo ""
    echo "All mkRoleVmTest generator tests passed"
  '';
in {
  vmRoleGeneratorTest =
    pkgs.runCommand "test-vm-role-generator" {}
    ''
      ${script}
      touch $out
    '';
}
