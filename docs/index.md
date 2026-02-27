# Documentation

This documentation follows the [Diataxis](https://diataxis.fr/) framework, organizing content by user need.

## Tutorials (Learning)

Step-by-step guides for learning:

- [Getting Started](tutorials/getting-started.md) - Set up this configuration on a new machine

## How-To Guides (Tasks)

Solve specific problems:

- [Add a New Machine](how-to/add-machine.md) - Configure a new Darwin or NixOS machine
- [Add a New Role](how-to/add-role.md) - Create a package bundle
- [Add a Custom Skill](how-to/add-skill.md) - Create an AI agent skill
- [Set Up 1Password SSH Signing](how-to/setup-1password.md) - Configure commit signing
- [Run CI Locally](how-to/run-ci-locally.md) - Validate before pushing

## Reference (Information)

Technical descriptions:

- [Options Reference](reference/options.md) - Configuration options (myConfig.*)
- [Roles Reference](reference/roles.md) - Available package bundles
- [Tasks Reference](reference/tasks.md) - Devenv task commands
- [Skills Reference](reference/skills.md) - Agent skill manifest format
- [CI/CD Reference](reference/ci.md) - Pipeline stages and tasks

## Explanation (Understanding)

Background and design:

- [Architecture](explanation/architecture.md) - How modules, bundles, and targets work
- [Agent Skills System](explanation/agent-skills.md) - Why skills are managed through Nix
