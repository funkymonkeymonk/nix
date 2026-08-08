# Cross-platform option guard tests
#
# Several role modules (desktop, creative, entertainment) branch their
# config on config.myConfig.isDarwin — installing different packages
# on macOS vs Linux, or NixOS-only options like programs.steam guarded
# by builtins.hasAttr "boot" options (to avoid infinite recursion when
# evaluated outside a real NixOS module tree).
#
# The existing role tests (test-roles.nix) only check that EXPECTED
# packages are present — they never verify that the platform-specific
# branches actually differ, or that a Darwin-only path stays absent on
# Linux and vice versa. Since myConfig.isDarwin's default is computed
# from pkgs.stdenv.hostPlatform.system (and the option is readOnly, so
# it can't be overridden via config), these tests build a second,
# Linux-flavored pkgs by overriding just the hostPlatform.system
# string — cheap and fast, no cross-compilation needed — and feed that
# into tests/stubs.nix so the whole stub module set (including
# _module.args.pkgs) reflects "we're on Linux" consistently.
{pkgs, ...}: let
  lib = pkgs.lib;

  # pkgs values that report as a specific host platform without doing any
  # actual cross-compilation. Everything else (the actual packages used in
  # nativeBuildInputs, etc.) still resolves against the real pkgs set — we
  # only need the platform string to flip isDarwin's default.
  #
  # IMPORTANT: These must override the system string explicitly; the test
  # runs on CI (x86_64-linux) where the ambient pkgs is Linux, so relying
  # on the ambient pkgs would make the "Darwin" test evaluate as Linux.
  darwinLikePkgs =
    pkgs
    // {
      stdenv =
        pkgs.stdenv
        // {
          hostPlatform =
            pkgs.stdenv.hostPlatform
            // {
              system = "aarch64-darwin";
            };
        };
    };

  linuxLikePkgs =
    pkgs
    // {
      stdenv =
        pkgs.stdenv
        // {
          hostPlatform =
            pkgs.stdenv.hostPlatform
            // {
              system = "x86_64-linux";
            };
        };
    };

  darwinStubs = import ./stubs.nix {pkgs = darwinLikePkgs;};
  linuxStubs = import ./stubs.nix {pkgs = linuxLikePkgs;};

  mkRoleEval = stubs: roleName:
    (lib.evalModules {
      modules =
        stubs.withRoles
        ++ [
          {
            config.myConfig = {
              users = [
                {
                  name = "testuser";
                  email = "test@example.com";
                  fullName = "Test User";
                  isAdmin = true;
                  sshIncludes = [];
                }
              ];
              roles.${roleName}.enable = true;
            };
          }
        ];
    })
    .config;

  packageNames = evaluated:
    map (p: p.name or (builtins.parseDrvName (p.pname or "unknown")).name)
    evaluated.environment.systemPackages;

  hasPkg = names: needle: builtins.any (n: lib.hasInfix needle n) names;

  # desktop role: Linux gets element-desktop + vivaldi via
  # environment.systemPackages; Darwin gets homebrew casks instead (no
  # equivalent systemPackages entries).
  desktopDarwin = mkRoleEval darwinStubs "desktop";
  desktopLinux = mkRoleEval linuxStubs "desktop";
  desktopDarwinPkgs = packageNames desktopDarwin;
  desktopLinuxPkgs = packageNames desktopLinux;

  # creative role: same package list (ffmpeg/imagemagick/pandoc) on
  # both platforms — homebrew casks are Darwin-only but don't touch
  # environment.systemPackages, so this is a control case confirming
  # the guard mechanism doesn't accidentally change the common path.
  creativeDarwin = mkRoleEval darwinStubs "creative";
  creativeLinux = mkRoleEval linuxStubs "creative";
in {
  crossPlatformDesktopGuardTest =
    pkgs.runCommand "test-cross-platform-desktop-guard"
    {}
    ''
      echo "=== Testing desktop role platform guard ==="

      ${
        if hasPkg desktopLinuxPkgs "element-desktop" && hasPkg desktopLinuxPkgs "vivaldi"
        then ''echo "  Linux gets element-desktop + vivaldi: OK"''
        else ''echo "  FAIL: Linux should have element-desktop + vivaldi, got [${builtins.concatStringsSep ", " desktopLinuxPkgs}]"; exit 1''
      }

      ${
        if !(hasPkg desktopDarwinPkgs "element-desktop") && !(hasPkg desktopDarwinPkgs "vivaldi")
        then ''echo "  Darwin does NOT get element-desktop/vivaldi (homebrew cask instead): OK"''
        else ''echo "  FAIL: Darwin should not have element-desktop/vivaldi in systemPackages, got [${builtins.concatStringsSep ", " desktopDarwinPkgs}]"; exit 1''
      }

      echo "desktop platform guard test passed"
      touch $out
    '';

  crossPlatformEntertainmentGuardTest =
    pkgs.runCommand "test-cross-platform-entertainment-guard"
    {}
    ''
      echo "=== Testing entertainment role platform guard (isNixOS module-definition-time check) ==="

      ${
        # entertainment.nix's isNixOS check is builtins.hasAttr "boot" options,
        # which is a module-*definition*-time check (not config-time), so it
        # doesn't depend on isDarwin at all -- it depends on whether a
        # boot option was declared in the module tree. Neither darwinStubs
        # nor linuxStubs declares options.boot, so isNixOS is false in both,
        # and the NixOS-only branch (programs.steam, obs-studio, discord)
        # should be absent from both -- confirming the guard doesn't fire
        # outside a real NixOS module tree (which is exactly what avoids
        # the infinite-recursion hazard the code comment warns about).
        let
          entertainmentDarwin = mkRoleEval darwinStubs "entertainment";
          entertainmentLinux = mkRoleEval linuxStubs "entertainment";
          darwinPkgs = packageNames entertainmentDarwin;
          linuxPkgs = packageNames entertainmentLinux;
        in
          if !(hasPkg darwinPkgs "obs-studio") && !(hasPkg linuxPkgs "obs-studio")
          then ''echo "  NixOS-only packages (obs-studio) absent outside real NixOS module tree on both platforms: OK"''
          else ''echo "  FAIL: obs-studio should not appear without a real NixOS module tree"; exit 1''
      }

      echo "entertainment platform guard test passed"
      touch $out
    '';

  crossPlatformCreativeControlTest =
    pkgs.runCommand "test-cross-platform-creative-control"
    {}
    ''
      echo "=== Testing creative role (control case: platform-independent packages) ==="

      ${
        let
          darwinPkgs = packageNames creativeDarwin;
          linuxPkgs = packageNames creativeLinux;
          bothHave = pkg: hasPkg darwinPkgs pkg && hasPkg linuxPkgs pkg;
        in
          if bothHave "ffmpeg" && bothHave "imagemagick" && bothHave "pandoc"
          then ''echo "  ffmpeg/imagemagick/pandoc present on both platforms: OK"''
          else ''echo "  FAIL: creative's platform-independent packages should match on both platforms"; exit 1''
      }

      echo "creative control test passed"
      touch $out
    '';
}
