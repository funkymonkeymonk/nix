# Documentation

This documentation follows the [Diataxis](https://diataxis.fr/) framework, organizing content by user need.

## Tutorials (Learning)

Step-by-step guides for learning:

- [Getting Started](tutorials/getting-started.md) - Set up this configuration on a new machine
- [Add Your Machine](tutorials/add-your-machine.md) - Add your own machine to this repo
- [Create Your First Role](tutorials/create-your-first-role.md) - Build a custom role module
- [Write Your First Skill](tutorials/write-your-first-skill.md) - Create an AI agent skill
- [Yak Shaving with yx](tutorials/yak-shaving.md) - Multi-agent task tracking with jj workspaces
- [Getting Started with jj](tutorials/jj-workflow.md) - Learn the jj version control workflow

## How-To Guides (Tasks)

Solve specific problems:

- [Add a New Machine](how-to/add-machine.md) - Configure a new Darwin or NixOS machine
- [Add a New Role](how-to/add-role.md) - Create a role module
- [Add a Custom Skill](how-to/add-skill.md) - Create an AI agent skill
- [Set Up 1Password SSH Signing](how-to/setup-1password.md) - Configure commit signing
- [Run CI Locally](how-to/run-ci-locally.md) - Validate before pushing
- [Create a PR with jj](how-to/create-pr-with-jj.md) - Create a pull request
- [Update an Existing PR](how-to/update-existing-pr.md) - Respond to review feedback
- [Sync with Main](how-to/sync-with-main.md) - Keep your branch up to date
- [Use jj Workspaces](how-to/use-workspaces.md) - Parallel development with workspaces
- [Create Stacked PRs](how-to/create-stacked-prs.md) - Stack dependent pull requests
- [Complete PR Workflow](how-to/complete-pr-workflow.md) - End-to-end with jj-finish
- [Create a Darwin System Daemon](how-to/create-darwin-daemon.md) - Add a launchd daemon service for macOS

## Reference (Information)

Technical descriptions:

- [Options Reference](reference/options.md) - Configuration options (myConfig.*)
- [Roles Reference](reference/roles.md) - Available role modules
- [Tasks Reference](reference/tasks.md) - Devenv task commands
- [Skills Reference](reference/skills.md) - Agent skill manifest format
- [Yaks Reference](reference/yaks.md) - yx task management commands
- [CI/CD Reference](reference/ci.md) - Pipeline stages and tasks
- [JJ Commands Reference](reference/jj-commands.md) - Jujutsu command reference

## Explanation (Understanding)

Background and design:

- [Architecture](explanation/architecture.md) - How modules, roles, and targets work
- [Agent Skills System](explanation/agent-skills.md) - Why skills are managed through Nix
- [Yaks and Workspaces](explanation/yaks-workspaces.md) - Multi-agent coordination design
- [JJ Mental Model](explanation/jj-mental-model.md) - Why jj works the way it does
