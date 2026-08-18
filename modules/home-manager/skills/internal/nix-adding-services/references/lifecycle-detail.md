# Adding a New Service — Full Lifecycle Detail

## Contents
- Step 1: Package the source (Node/Rust-Go/Python)
- Step 2: Register the package
- Step 3: Add options
- Step 4: Create the service module (Darwin/NixOS)
- Step 5: Add secrets (opnix)
- Step 6: Create home-manager module
- Step 7: Add tests
- Step 8: Wire into the target
- Step 9: Validate

## Step 1: Package the Source

### Node.js / npm (buildNpmPackage)

```nix
buildNpmPackage rec {
  pname = "my-service";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "org";
    repo = "my-service";
    rev = "v${version}";
    hash = "sha256-...";
  };

  npmDepsHash = "sha256-...";

  # Compute npmDepsHash:
  # 1. Set npmDepsHash = lib.fakeHash
  # 2. Run: nix build .#my-service
  # 3. Error message shows the actual hash — paste it in
  #
  # If project uses yarn.lock (not package-lock.json):
  # 1. Generate package-lock.json: rm yarn.lock; npm install --package-lock-only --legacy-peer-deps
  # 2. Copy it into packages/my-service/package-lock.json
  # 3. Add postPatch: cp ${./package-lock.json} package-lock.json
  # 4. Add: npmFlags = ["--legacy-peer-deps"];

  installPhase = ''
    mkdir -p $out/lib/my-service $out/bin
    cp -r .next/standalone/* $out/lib/my-service/
    cp -r public $out/lib/my-service/
    cp -r .next $out/lib/my-service/.next
    cp -r drizzle $out/lib/my-service/drizzle
    makeWrapper ${nodejs}/bin/node $out/bin/my-service \
      --chdir "$out/lib/my-service" \
      --add-flags "$out/lib/my-service/server.js"
  '';
}
```

**Gotchas:**
- `buildNpmPackage` needs `package-lock.json` — convert from `yarn.lock` via `npm install --package-lock-only`
- Font fetches fail in sandbox — patch with `sed` in `preBuild`
- Standalone output needs `.next/`, `public/`, `node_modules/`

### Go (buildGoModule)

```nix
buildGoModule rec {
  pname = "my-service";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "org";
    repo = "my-service";
    rev = "v${version}";
    hash = "sha256-...";
  };

  vendorHash = "sha256-...";
  # Compute vendorHash the same way as npmDepsHash:
  # 1. Set vendorHash = lib.fakeHash
  # 2. Run: nix build .#my-service
  # 3. Error message shows the actual hash — paste it in

  # If the repo has multiple binaries/cmd dirs, narrow the build:
  # subPackages = ["cmd/my-service"];

  meta.mainProgram = "my-service";
}
```

### Rust (buildRustPackage)

```nix
rustPlatform.buildRustPackage rec {
  pname = "my-service";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "org";
    repo = "my-service";
    rev = "v${version}";
    hash = "sha256-...";
  };

  cargoHash = "sha256-...";
  # Compute the same way: set lib.fakeHash, build, paste in the real hash from the error

  meta.mainProgram = "my-service";
}
```

### Homebrew fallback (skip Nix packaging entirely)

If the service already has a Homebrew formula and you don't need a reproducible Nix build, skip packaging and reference the existing tool directly:

```nix
launchd.daemons.my-service = {
  serviceConfig = {
    ProgramArguments = ["/opt/homebrew/bin/my-service" "serve"];
    UserName = primaryUser;
    ...
  };
};
```

### Python (via nixpkgs)

If the package is in nixpkgs, no overlay needed — just use it directly:

```nix
{ pkgs, ... }:
{pkgs.searxng}
```

## Step 2: Register the Package

### Add to overlay (if building from source)

```nix
# overlays/default.nix
final: _prev: {
  my-service = final.callPackage ../packages/my-service {};
}
```

### Export as flake package (optional)

```nix
# flake.nix
inherit (pkgs) rtk yaks my-service;
```

## Step 3: Add Options

```nix
# modules/common/options.nix — inside the relevant config block
myService = {
  enable = mkOption {
    type = types.bool;
    default = false;
    description = "Enable my-service";
  };

  port = mkOption {
    type = types.port;
    default = 8080;
    description = "Port for my-service";
  };
};
```

For simple services with few options, add inline. For services with 10+ options, create a dedicated submodule.

## Step 4: Create the Service Module

### Shared config (optional)

```nix
# modules/services/my-service/common.nix
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.myConfig.myService;
in {
  options._myServiceCommon = mkOption {
    type = types.attrs;
    internal = true;
  };
  config._myServiceCommon = {
    inherit (cfg) port;
  };
}
```

### Darwin (launchd daemon)

```nix
# modules/services/my-service/darwin.nix
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.myConfig.myService;
  primaryUser = (builtins.head config.myConfig.users).name;
  darwinHomeDir = "/Users/${primaryUser}";

  serviceScript = pkgs.writeShellScript "my-service-launchd" ''
    exec ${pkgs.my-service}/bin/my-service
  '';
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    launchd.daemons.my-service = {
      serviceConfig = {
        Label = "com.my-service";
        UserName = primaryUser;
        ProgramArguments = ["${serviceScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/my-service.log";
        StandardErrorPath = "/tmp/my-service.error.log";
        WorkingDirectory = "${darwinHomeDir}/.local/share/my-service";
        EnvironmentVariables = {
          KEY = "value";
        };
      };
    };
  };
}
```

**Key rules:**
- Use `launchd.daemons` (not `user.agents`) so nix-darwin auto-reloads on switch
- Always set `UserName` to run as the user, not root
- Expand `$HOME` manually — launchd does NOT expand env vars in plist paths
- Use `writeShellScript` (not `writeShellScriptBin`) for the launcher script

### NixOS (systemd)

If the service should also work on Linux:

```nix
# modules/services/my-service/nixos.nix
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.myConfig.myService;
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    systemd.services.my-service = {
      description = "My Service";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${pkgs.my-service}/bin/my-service";
        User = primaryUser;
        Restart = "always";
      };
      environment = {
        KEY = "value";
      };
    };
  };
}
```

## Step 5: Add Secrets (opnix)

If the service needs API keys from 1Password — see the `nix-opnix-secrets` skill for the full pattern. Quick version:

```nix
# modules/home-manager/my-service.nix
let
  hmLib = import ./lib.nix {inherit lib;};
  opnixSecrets = hmLib.mkOpnixSecretsGeneric "my-service"
    osConfig.myConfig.onepassword.defaultVault [{
      reference = "op://Vault/Item Name/credential";
      path = ".config/my-service/secrets/key";
    }];

  patchScript = pkgs.writeShellScript "patch-my-service-keys" ''
    KEY=$(cat "$HOME/.config/my-service/secrets/key")
    sed -i.bak -e "s/API_KEY_PLACEHOLDER/$KEY/" "$HOME/.config/my-service/config"
  '';
in {
  config = mkIf cfg.enable {
    programs.onepassword-secrets = {
      enable = true;
      secrets = opnixSecrets;
    };
    home.activation.patchMyServiceKeys = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${patchScript}
    '';
  };
}
```

**Activation ordering:**
- `writeBoundary` — after config files, before opnix resolves
- `installPackages` — after opnix resolves (use if the secret file isn't ready at writeBoundary)

## Step 6: Create Home-Manager Module (if needed)

For services with user-level config files (TOML, JSON, YAML):

```nix
# modules/home-manager/my-service.nix
{ osConfig, lib, pkgs, ... }:
with lib; let
  cfg = osConfig.myConfig.myService;
  tomlFormat = pkgs.formats.toml {};

  configFile = tomlFormat.generate "config.toml" {
    server = {
      host = cfg.host;
      port = cfg.port;
    };
  };
in {
  config = mkIf cfg.enable {
    xdg.configFile."my-service/config.toml" = {
      source = configFile;
      force = true;
    };
  };
}
```

**When to force refresh:**
- `force = true` — overwrites on every rebuild (Nix-managed config)
- `force = false` — only creates if missing (user can customize)

For configs with secrets from opnix, force-refresh the base config and patch in the secrets during activation.

## Step 7: Add Tests

```nix
# tests/test-my-service.nix
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubModules = [
    ../modules/common/options.nix
    { config._module.args = {inherit pkgs;}; }
  ];

  myServiceDefaults = (lib.evalModules {
    modules = stubModules;
  }).config.myConfig.myService;

  myServiceCustom = (lib.evalModules {
    modules = stubModules ++ [{
      config.myConfig.myService.enable = true;
      config.myConfig.myService.port = 9090;
    }];
  }).config.myConfig.myService;
in {
  myServiceOptionsTest = pkgs.runCommand "test-my-service" {} ''
    # Test defaults
    ${if myServiceDefaults.port == 8080
      then ''echo "port default: OK"''
      else ''echo "port default FAIL"; exit 1''}

    # Test custom values
    ${if myServiceCustom.port == 9090
      then ''echo "port custom: OK"''
      else ''echo "port custom FAIL"; exit 1''}

    touch $out
  '';
}
```

Register in `tests/default.nix`, `tests/test-coverage.nix`, and add the check to `flake.nix`:

```nix
# flake.nix — in the checks section
my-service-options
```

## Step 8: Wire Into the Target

```nix
# targets/MegamanX/default.nix
myConfig = {
  my-service = {
    enable = true;
    port = 8080;
  };
};
```

```nix
# flake.nix — import the service module
./modules/services/my-service/darwin.nix
```

## Step 9: Validate

```bash
# 1. Build
nix build .#darwinConfigurations.MegamanX.config.system.build.toplevel

# 2. Run tests
nix build .#checks.aarch64-darwin.my-service-options

# 3. Switch
devenv tasks run system:switch

# 4. Verify
curl http://localhost:8080/health
cat /tmp/my-service.log
cat /tmp/my-service.error.log
```
