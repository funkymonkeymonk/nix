# Shared helper module for nix-unit tests
# Provides a reusable evalModules setup that mirrors the real module system enough
# to test options, roles, and service modules without building full configurations.
{
  pkgs,
  nix-unit,
}: let
  inherit (pkgs) lib;
  inherit (nix-unit.lib {inherit lib;}) fileset makeTestSuite runTests;

  # Stub modules that provide minimal options needed by our module system.
  # These are intentionally lightweight — we test the module outputs, not the
  # full NixOS/Darwin runtime.
  stubModules = [
    ../modules/common/options.nix
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

  # Extended stubs for modules that reference roles, users, etc.
  roleStubModules =
    stubModules
    ++ [
      ../modules/roles/default.nix
      {
        options.users = lib.mkOption {
          type = lib.types.anything;
          default = {};
        };
      }
    ];

  # Helper: evaluate with a specific role enabled + test user
  evalWithRole = roleName: extraConfig:
    (lib.evalModules {
      modules =
        roleStubModules
        ++ [
          {
            config.myConfig =
              {
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
              }
              // (
                if extraConfig == null
                then {}
                else extraConfig
              );
          }
        ];
    }).config;

  # Helper: evaluate with custom config only
  evalWithConfig = extraConfig:
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig = extraConfig;
          }
        ];
    }).config;

  # Helper for evaluating service module stubs
  vaneDarwinStubs = [
    ../modules/common/options.nix
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
        shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
      };
      options.launchd.user.agents = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.system.activationScripts = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # Helper to assert equality in nix-unit tests
  # Returns a test attribute set for use with nix-unit's makeTestSuite
  mkAssertion = desc: expr: expected: let
    result = expr;
    match =
      if result == expected
      then true
      else false;
  in {
    inherit desc;
    expr = match;
    expected = true;
  };

  # Run nix-unit test suite and wrap as a nix build check
  mkTestCheck = name: suite:
    runTests "test-${name}" [fileset] false suite;
in {
  inherit stubModules roleStubModules evalWithRole evalWithConfig vaneDarwinStubs;
  inherit mkAssertion mkTestCheck makeTestSuite;
}
