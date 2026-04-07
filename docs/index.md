---
title: "Documentation Index"
description: "Complete documentation index for LLM navigation. Diataxis framework: Tutorials, How-To Guides, Reference, Explanation."
type: reference
audience: both
last-reviewed: 2026-04-06
---

# Documentation

This documentation follows the [Diataxis](https://diataxis.fr/) framework, organizing content by user need:

- **Tutorials**: Learning-oriented, step-by-step experiences
- **How-To Guides**: Goal-oriented, task completion
- **Reference**: Information-oriented, technical details
- **Explanation**: Understanding-oriented, background and design

<!-- LLM: NAVIGATION SECTION - Use this to find relevant docs -->

## Quick Navigation

| I want to... | See |
|--------------|-----|
| Set up OpenClaw AI quickly | [Automated OpenClaw Setup](how-to/setup-openclaw-microvm-automated.md) |
| Learn the basics | [Getting Started](tutorials/getting-started.md) |
| Deploy a MicroVM | [Set up MicroVM Host](how-to/setup-microvm-host.md) |
| Install disposable NixOS | [Install Disposable](how-to/install-disposable.md) |
| Configure a new machine | [Add a New Machine](how-to/add-machine.md) |
| Find configuration options | [Options Reference](reference/options.md) |
| Understand the architecture | [Architecture](explanation/architecture.md) |

<!-- LLM: END NAVIGATION -->

---

## Tutorials (Learning)

Step-by-step guides for learning:

### Getting Started
- [Getting Started](tutorials/getting-started.md) - Set up this configuration on a new machine

---

## How-To Guides (Tasks)

Solve specific problems:

### Machine Setup
- [Add a New Machine](how-to/add-machine.md) - Configure a new Darwin or NixOS machine
- [Install Disposable](how-to/install-disposable.md) - Deploy disposable NixOS machines
- [Install Disposable Quick Reference](how-to/install-disposable-quick-reference.md) - Quick reference
- [Set Up MicroVM Host](how-to/setup-microvm-host.md) - Configure a server for MicroVMs

### AI Assistant Deployment (MicroVM)
- **[Set Up OpenClaw MicroVM (Automated)](how-to/setup-openclaw-microvm-automated.md)** - Deploy OpenClaw with cloud-init automation ⭐ **LLM-Optimized**
- [Set Up OpenClaw MicroVM](how-to/setup-openclaw-microvm.md) - Full setup with Matrix integration
- [Set Up Matrix Synapse MicroVM](how-to/setup-matrix-microvm.md) - Self-hosted chat server

### Development
- [Add a New Role](how-to/add-role.md) - Create a role module
- [Add a Custom Skill](how-to/add-skill.md) - Create an AI agent skill
- [Run CI Locally](how-to/run-ci-locally.md) - Validate before pushing

### Configuration
- [Set Up 1Password SSH Signing](how-to/setup-1password.md) - Configure commit signing
- [Deploy MicroVM via GitHub](how-to/deploy-microvm-github.md) - GitHub Actions deployment
- [Create Installer USB](how-to/create-installer-usb.md) - NixOS installation media
- [Fix Pre-commit Hooks](how-to/fix-precommit-hooks.md) - Troubleshoot git hooks

---

## Reference (Information)

Technical descriptions:

### Configuration
- [Options Reference](reference/options.md) - Configuration options (myConfig.*)
- [Roles Reference](reference/roles.md) - Available role modules
- [Skills Reference](reference/skills.md) - Agent skill manifest format

### Commands
- [Tasks Reference](reference/tasks.md) - Devenv task commands
- [Yaks Reference](reference/yaks.md) - Yaks tool reference

### Infrastructure
- [CI/CD Reference](reference/ci.md) - Pipeline stages and tasks

---

## Explanation (Understanding)

Background and design:

- [Architecture](explanation/architecture.md) - How modules, roles, and targets work
- [Agent Skills System](explanation/agent-skills.md) - Why skills are managed through Nix
- [Yaks Workspaces](explanation/yaks-workspaces.md) - Workspace management

---

## For AI Agents

<!-- LLM: AGENT-SPECIFIC SECTION -->

### Agent Quick Start

If you're an AI agent reading this, see:

1. **[AGENTS.md](../AGENTS.md)** - Complete agent guide for this repository
2. **[setup-openclaw-microvm-automated.md](how-to/setup-openclaw-microvm-automated.md)** - Deploy yourself in a MicroVM

### Automation-Ready Guides

These guides are designed for automated execution:

| Guide | Automation Level |
|-------|-----------------|
| [Set Up OpenClaw MicroVM (Automated)](how-to/setup-openclaw-microvm-automated.md) | Full automation with verification |
| [Run CI Locally](how-to/run-ci-locally.md) | Command sequences |
| [Add a New Role](how-to/add-role.md) | Step-by-step with templates |

### Key Documents for LLMs

- **Architecture**: [explanation/architecture.md](explanation/architecture.md) - Understand the system
- **Options**: [reference/options.md](reference/options.md) - Available configuration
- **Roles**: [reference/roles.md](reference/roles.md) - What modules do
- **Testing**: See [AGENTS.md](../AGENTS.md) testing section

<!-- LLM: END AGENT-SPECIFIC -->

---

## Document Metadata

<!-- LLM: Use this metadata for context -->

| Property | Value |
|----------|-------|
| Framework | Diataxis |
| Structure | tutorials/ how-to/ reference/ explanation/ |
| Last Reviewed | 2026-04-06 |
| Repository | https://github.com/funkymonkeymonk/nix |
| Main Branch | main |

<!-- LLM: END METADATA -->
