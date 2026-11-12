# Agent Skills

The public `funkymonkeymonk/skills` repository is the source of all standalone
agent skills in this Nix flake. The flake consumes it as a raw input with
`flake = false`; `flake.lock` pins the exact source revision.

Home Manager finds each directory under `skills/` that contains `SKILL.md`.
It links the complete directory, including supporting files, to
`~/.agents/skills/<name>/`. OpenCode and Pi discover that location. Claude Code
receives the same directories through its Home Manager skill option.

All repository skills install when `developer`, `creative`, `workstation`,
`opencode`, `claude`, or `pi` is enabled. The Nix manifest stores optional
metadata; it does not contain skill content or select which repository skills
are installed. There is no activation-time network fetch or `npx skills add`
step.

## Update the source revision

Run this command from the Nix flake repository:

```bash
nix flake update personal-skills
```

This updates the pinned revision in `flake.lock`. Build or switch the machine
to deploy the updated skills.

## Add or change a skill

1. Add or edit a directory under `skills/` in the skills repository.
2. Include a valid `SKILL.md` file. Keep supporting files in that directory.
3. Push the change to the skills repository.
4. Run `nix flake update personal-skills` in the Nix repository.
5. Run `devenv tasks run check:lint` and `devenv tasks run test:eval`.
6. Rebuild the machine configuration.
7. Run `find ~/.agents/skills -name SKILL.md -print` to list installed skills.

Use the source repository's [README](https://github.com/funkymonkeymonk/skills)
for skill authoring and validation details.
