# Shared stub module lists for use in evalModules-based tests.
#
# Usage:
#   { pkgs, ... }: let
#     stubs = import ./stubs.nix { inherit pkgs; };
#   in {
#     # basic option test
#     modules = stubs.base;
#
#     # test a Darwin service module
#     modules = stubs.base ++ stubs.darwinService ++ [ ../modules/services/foo/darwin.nix ];
#
#     # test a role that needs onepassword + roles/default.nix
#     modules = stubs.withRoles;
#   }
#
# Composition rules:
#   stubs.base            — always start here (options.nix + platform + env + pkgs args)
#   stubs.darwinService   — add for modules that set launchd.daemons or system.activationScripts
#   stubs.nixosService    — add for modules that set networking / systemd / services
#   stubs.nixosServices   — adds a bare `services` option stub (for aerospace, openssh, etc.)
#   stubs.onepassword     — add for modules/tests that use myConfig.onepassword
#   stubs.withRoles       — base ++ roles/default.nix ++ onepassword (most role tests)
#
# Per-module stubs:
#   stubs.microvm         — base ++ nixosService ++ microvm/default.nix
#   stubs.agentSkills     — base ++ roles/agent-skills.nix
#   stubs.aerospace       — base ++ nixosServices ++ home-manager/aerospace.nix
#   stubs.vane            — base ++ darwinService ++ services/vane/darwin.nix
#   stubs.searxng         — base ++ darwinService ++ services/searxng/darwin.nix
#   stubs.bifrost         — base ++ darwinService ++ services/bifrost/darwin.nix
#   stubs.caddy           — base ++ darwinService ++ services/caddy/darwin.nix
#
{pkgs}: let
  lib = pkgs.lib;

  # ── Primitives ────────────────────────────────────────────────────────────
  # Lowest-level building blocks. Combine these instead of repeating inline.

  # Stubs the nixpkgs.hostPlatform option (required by options.nix isDarwin).
  hostPlatformStub = {
    options.nixpkgs.hostPlatform = lib.mkOption {
      type = lib.types.anything;
      default = {inherit (pkgs.stdenv.hostPlatform) system;};
    };
  };

  # Injects pkgs into _module.args so module files can use `pkgs`.
  moduleArgsStub = {
    config._module.args = {inherit pkgs;};
  };

  # Stubs the environment options set by NixOS / nix-darwin and referenced
  # by most modules.  Includes all sub-options seen across the test suite.
  envStub = {
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
      etc = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    };
  };

  # Stubs programs, homebrew, users, and microvm — broad options that many
  # role / service modules reference without needing real values.
  broadStub = {
    options.programs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
    options.homebrew = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    options.users = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    options.microvm = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    config.microvm.vms = {};
  };

  # ── Composite stubs ───────────────────────────────────────────────────────

  # Darwin launchd service stubs — required when a module sets launchd.daemons
  # or system.activationScripts (e.g. vane, searxng, bifrost, caddy).
  darwinServiceStub = {
    options.launchd.daemons = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
    options.system.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
  };

  # NixOS service stubs — required when a module sets networking, systemd
  # services, or system.stateVersion (e.g. microvm/default.nix).
  nixosServiceStub = {
    options.networking = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    options.systemd.services = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
    };
    options.services = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
    options.system.stateVersion = lib.mkOption {
      type = lib.types.anything;
      default = null;
    };
  };

  # Bare `services` option stub — required when a module reads/writes
  # services.* but doesn't need full NixOS networking (e.g. aerospace).
  servicesStub = {
    options.services = lib.mkOption {
      type = lib.types.anything;
      default = {};
    };
  };
in rec {
  # ── Primary stub lists ────────────────────────────────────────────────────

  # base: the universal starting point for every test.
  # Provides: options.nix, hostPlatform, environment.*, programs, homebrew,
  #           users, microvm, and _module.args.pkgs.
  base = [
    ../modules/common/options.nix
    ../modules/common/llm-client.nix
    ../modules/common/charm.nix
    ../modules/common/syncthing.nix
    ../modules/common/zellij.nix
    hostPlatformStub
    envStub
    broadStub
    moduleArgsStub
  ];

  # darwinService: add to base for modules that write launchd.daemons or
  # system.activationScripts (Darwin service modules).
  darwinService = [darwinServiceStub];

  # nixosService: add to base for modules that write networking/systemd/services
  # (NixOS service modules, e.g. microvm/default.nix).
  nixosService = [nixosServiceStub];

  # services: add to base for modules that only need a bare `services` option
  # (e.g. aerospace, openssh, without the full NixOS networking stubs).
  nixosServices = [servicesStub];

  # onepassword: add to base when myConfig.onepassword is accessed.
  # Required by: foundation role, opencode/claude/pi roles via roles/default.nix.
  onepassword = [../modules/common/onepassword.nix];

  # withRoles: base + roles/default.nix + onepassword.
  # Use for tests that evaluate role modules (test-roles.nix, test-email.nix, etc.).
  withRoles = base ++ [../modules/roles/default.nix] ++ onepassword;

  # ── Per-module prebuilt stubs ─────────────────────────────────────────────

  # Stubs for modules/microvm/default.nix
  microvm =
    base
    ++ nixosService
    ++ [../modules/microvm/default.nix];

  # Stubs for modules/roles/agent-skills.nix
  agentSkills = base ++ [../modules/roles/agent-skills.nix];

  # Stubs for modules/home-manager/aerospace.nix
  # (declares myConfig.aerospace.externalMonitor; sets services.aerospace +
  #  environment.systemPackages — needs servicesStub on top of base)
  aerospace =
    base
    ++ nixosServices
    ++ [../modules/home-manager/aerospace.nix];

  # Darwin service module stubs (base + launchd/activationScripts + module)
  vane = base ++ darwinService ++ [../modules/services/vane/darwin.nix];
  searxng = base ++ darwinService ++ [../modules/services/searxng/darwin.nix];
  bifrost = base ++ darwinService ++ [../modules/services/bifrost/darwin.nix];
  caddy = base ++ darwinService ++ [../modules/services/caddy/darwin.nix];
}
