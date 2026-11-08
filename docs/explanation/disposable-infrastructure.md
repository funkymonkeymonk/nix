---
title: "Disposable Infrastructure"
description: "How reusable NixOS archetypes, machine records, and generated hardware facts fit together"
type: explanation
audience: both
last-reviewed: 2026-11-07
---

# Disposable Infrastructure

This repository uses reusable NixOS profiles to make some systems easier to replace or reinstall. “Disposable” describes how much configuration is shared and how the machine is provisioned; it does **not** mean the machine has no named configuration or no catalog record.

## Machine identity and reusable behavior are separate

Every named NixOS or Darwin output has a record in `library/machines/catalog.nix`. The catalog supplies the output name, platform, hostname, secrets profile, deployment metadata, and the modules used to compose that output. Flake-parts projects those records into `nixosConfigurations` and `darwinConfigurations`; other tooling uses the same inventory.

A machine module under `machines/<name>/` sets NixOS or Darwin options that are specific to that system. It is optional when the catalog and shared archetypes already describe the configuration. For example, `type-server` is composed from the shared server archetype and disk/hardware inputs without needing an otherwise-empty machine module. `zero` has a machine module because it contains gaming, user, and hardware-specific settings.

The catalog and a machine module therefore serve different purposes: the catalog describes the output and assembles its modules; the machine module supplies system configuration. Keep platform and hostname in the catalog rather than repeating them in the machine module.

## What “disposable” means here

Standardized NixOS configurations use shared archetypes, declarative disk layouts, and—where appropriate—NixOS Facter reports instead of hand-maintained hardware configuration. This reduces per-system setup and makes reinstalling a system more repeatable. It does not make every machine interchangeable: disk layout, persistent data, credentials, hardware, and service settings can still be machine-specific.

Examples include:

- `type-server` and `type-server-arm`, which reuse the server archetype while retaining different output platforms and machine records.
- `type-nas`, which combines the headless-server archetype with NAS-specific storage and services.
- `drlight`, which uses shared server, media-center, and observability profiles plus its own media and storage configuration.
- `zero`, which has a more bespoke desktop and gaming configuration.

Disko layouts and hardware discovery are inputs to machine composition, not substitutes for the machine catalog. Facter is used only by configurations that import the Facter hardware module; other systems can use explicit hardware configuration.

## Why keep a catalog?

The catalog provides one source of machine identity and output metadata to flake generation, deployment tooling, and machine inventory consumers. A module alone does not say which flake output name, platform, secret profile, or installation metadata should be associated with it. Keeping that registry separate also prevents the machine’s option-level configuration from being mixed into one large inventory file.

The catalog is intentionally not a copy of the machine module. It selects the module stack and carries output metadata; the module sets system options. Shared constructors in the catalog provide common builder defaults so those defaults do not need to be repeated in every record.

## Related documents

- [Architecture](architecture.md) explains how modules, archetypes, machine modules, and catalog records fit together.
- [Set Up Your NixOS Machine](../tutorials/setup-your-nixos-machine.md) covers the guarded live-USB installation workflow.
