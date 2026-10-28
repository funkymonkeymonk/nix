# Tasks Reference

Tasks are defined in `devenv.nix` and provide common operations.

## Running Tasks

```bash
devenv tasks run <task-name>
```

Or use the shell alias:
```bash
dt <task-name>
dtr <task-name>
```

List all tasks:
```bash
devenv tasks list
dtl
```

## Task Conventions

Tasks follow a `namespace:action` naming convention:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `*:all` | **Aggregate** — runs all tasks in the namespace | `check:all`, `test:all` |
| `*:name` | **Leaf** — specific operation | `check:lint`, `test:eval` |

Run the aggregate when you want everything in a category. Run the leaf when you want a specific thing.

## Available Tasks

### Quality Checks

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `check:all` | Lint + unit tests + config eval | ~30s |
| `check:lint` | Formatting (alejandra), dead code (deadnix), static analysis (statix), YAML | ~10s |
| `check:unit` | nix-unit eval tests (fast, no builds) | ~5s |

### Testing

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `test:all` | Eval + build checks + module tests | 2–10min |
| `test:eval` | Evaluate all NixOS and Darwin configurations | ~10s |
| `test:build` | Build all flake check targets (single eval) | 2–10min |
| `test:sketchybar` | Sketchybar module tests | ~30s |
| `test:onepassword` | 1Password module tests | ~30s |

### Documentation

| Task | Description |
|------|-------------|
| `docs:all` | Update + validate + generate |
| `docs:update` | Update and validate documentation (Diataxis) |
| `docs:validate` | Validate documentation structure only |
| `docs:generate` | Generate reference documentation only |

### System

| Task | Description |
|------|-------------|
| `system:switch` | Apply configuration to current system (platform-aware) |
| `system:init` | Initial nix-darwin setup (macOS only) |

### Named Machine Operations

| Task | Required input | Description |
|------|----------------|-------------|
| `machines:info` | none | List the declared catalog without selecting a target |
| `machines:build` | `machine` | Build one local machine role; does not contact the target |
| `machines:check` | `machine` | Check declared remote access for one machine |
| `machines:plan` | `machine` | Create a review plan for one explicitly named machine |
| `machines:apply` | `machine`, `planId` | Apply a reviewed plan ID using the named machine's scoped profile |
| `machines:deploy` | `machine`; optional `useMachinesAsBuilders` | Interactively deploy one explicitly named machine, optionally using reachable catalog targets as Nix builders |
| `machines:install` | `machine` | Install one named target after a destructive-disk confirmation |

Supply task inputs with `--input`; none of the machine operations defaults to all
catalog entries:

```bash
devenv tasks run machines:info
devenv tasks run machines:build --input machine=zero
devenv tasks run machines:check --input machine=zero
devenv tasks run machines:plan --input machine=zero
devenv tasks run machines:apply --input machine=zero --input planId=plan-123
devenv tasks run machines:deploy --input machine=zero
devenv tasks run machines:deploy --input machine=MegamanX --input useMachinesAsBuilders=true
devenv tasks run machines:install --input machine=zero
```

The build task uses `devenv build machines.<name>.build.nixos` for NixOS and
`.build.nix-darwin` for nix-darwin. Builds are local; set up a compatible remote
builder separately when the build system differs from the workstation. For an
interactive deploy on a different architecture, set `useMachinesAsBuilders=true`;
Devenv can then use reachable catalog targets as Nix builders. For a
NixOS machine with facter enabled, for example
`devenv build machines.zero.build.nixos`, the build requires the actual
`.machines/zero/facter.json` report. The named `machines install` workflow
generates it from the target. Never fabricate, copy from another host, or
commit a guessed report. If using a real hand-written
`hardware-configuration.nix` instead, import that file in the machine module
and explicitly disable facter locally (for example,
`hardware.facter.reportPath = lib.mkForce null;`).

Remote operations inspect the selected SecretSpec profile before execution. If
that profile declares secrets, the wrapper runs only that operation through
`secretspec run --profile <catalog-profile> -- ...`; profiles with no declared
secrets bypass SecretSpec. The current Homelab and Personal profiles contain no
secret declarations, so `check`, `plan`, `apply`, and `deploy` run directly. A
fresh-host `install` is rejected unless its selected profile explicitly declares
`OPNIX_SERVICE_ACCOUNT_TOKEN` with an approved default-vault SecretSpec reference;
an unrelated API key does not satisfy this prerequisite. The current profiles stay
empty until the user confirms a real secret item, so installs remain fail-closed.
`Homelab` is selected for `zero`, `drlight`, `type-nas`,
`type-server`, and `type-server-arm`, matching the Homelab default configured by
their headless NixOS archetype. Other catalog entries use the shared `Personal`
default. `info` and local `build` do not load SecretSpec. SecretSpec remains
disabled during devenv configuration/shell evaluation; no token or secret value
is put in task input.

Remote endpoints are not inferred from the workstation hostname and no personal
IP is committed. Set `machines.<name>.target.host` in the ignored
`devenv.local.nix` override, or point it at a verified SSH alias. A nix-darwin
target needs an administrator account with passwordless `sudo`. Cross-platform
builds that use a machine as a Nix builder require SSH access through the local
SSH configuration; `target.sshOpts` do not configure builder connections. For example,
create this ignored local override:

```nix
{...}: {
  machines.zero.target.host = "zero-ssh";
}
```

For a fresh ISO target, first add an SSH alias in `~/.ssh/config` using the
address and fingerprint reported by the live image; substitute the displayed
address locally rather than committing it:

```sshconfig
Host zero-ssh
  HostName <address-reported-by-ISO>
  # Set User only to the account allowed by the target's approved SSH policy.
```

Then set that explicit alias as the named machine's target. The existing
headless NixOS targets (`type-nas`, `type-server`, `type-server-arm`, and
`drlight`) retain their root-SSH restrictions; this workflow does not change SSH
or sudo policy, so deployments to those targets remain blocked until their
access configuration is reviewed separately. The installer ISO access setup is
covered by its own task.

`machines:install` prints a disk-erasure warning and proceeds only after the
operator types `yes`. NixOS installation requires root SSH. Existing headless
NixOS roles currently deny root login; do not treat them as installable or
change their SSH/sudo policy until access is separately reviewed and approved.
Fresh-host install also fails closed until `OPNIX_SERVICE_ACCOUNT_TOKEN` is
declared in the selected profile with an owner-confirmed item/field reference
in the machine's default vault. The committed Homelab and Personal profiles
are intentionally empty, so this prerequisite is not currently satisfied.
`machines:deploy` remains interactive and never adds `--yes`. The optional
`useMachinesAsBuilders` input maps to Devenv's `--use-machines-as-builders`
flag; use it only when the explicitly configured target is reachable and can
build for its own architecture. The apply wrapper
reads the saved plan JSON from `$DEVENV_DOTFILE/machine-plans/<plan-id>/plan.json`
(or the project `.devenv/machine-plans/<plan-id>/plan.json` fallback when
`DEVENV_DOTFILE` is unset). It accepts only a Devenv plan ID—not a file path—and
requires the plan's `machines` map to contain exactly the explicitly named
machine. A plan for another machine, a fleet plan, or a missing/malformed plan is
rejected before SecretSpec or `devenv machines apply` runs. The SecretSpec
profile is selected from that verified machine name. Thus apply is bound to the
single machine named when the plan was created; use `machines:plan <name>`, review
that plan, and apply its resulting ID.

### Validation

| Task | Description |
|------|-------------|
| `validate:all` | Disko + install-script validation |
| `validate:disko` | Validate disko disk configurations |
| `validate:install-script` | Validate install-machine.sh syntax |

### Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:all` | Status + update + validate |
| `agent-skills:status` | Check skills installation status |
| `agent-skills:update` | Update skills from upstream superpowers |
| `agent-skills:validate` | Validate skills format |

### LLM / Benchmarking

| Task | Description |
|------|-------------|
| `benchmark:all` | Run all benchmark suites |
| `benchmark:lm-eval-gsm8k` | lm-eval GSM8K against local oMLX |
| `benchmark:lm-eval-mini` | Quick lm-eval smoke benchmark |
| `benchmark:lm-eval-leaderboard` | HuggingFace Open LLM Leaderboard v2 |
| `benchmark:lighteval-gsm8k` | lighteval GSM8K |
| `benchmark:bfcl-smoke` | BFCL function-calling smoke test against local oMLX |
| `profile:llm` | Profile LLM inference performance |
| `smoke:llm-stack` | Smoke test oMLX + Bifrost |

### Maintenance

| Task | Description |
|------|-------------|
| `flake:update` | Update flake inputs to latest versions |

## Dependency Graph

The `*:all` aggregates use devenv's `after` mechanism to run leaves in the correct order:

```
check:all
├── check:lint
└── check:unit
    └── test:eval

test:all
├── test:eval
├── test:build
├── test:sketchybar
└── test:onepassword
```

Dependencies are declared, not orchestrated via shell — devenv handles scheduling.

## Shell Aliases

After entering the devenv shell:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |
| `s` | `devenv tasks run system:switch` |
| `switch` | `devenv tasks run system:switch` |
