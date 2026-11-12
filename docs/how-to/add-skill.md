---
title: "Update or Add an Agent Skill"
description: "Update the Nix flake to deploy skills from the personal skills repository"
type: how-to
audience: agent
last-reviewed: 2026-11-11
---

# Update or Add an Agent Skill

Use this guide to add or change a skill in the public skills repository and
deploy it through the personal Nix flake.

1. Open the skills repository and add or edit a directory under `skills/`.
2. Add a valid `SKILL.md` file to the directory.
3. Keep required scripts, references, and other support files in that directory.
4. Validate the skill with the skills repository's documented checks.
5. Push the change to the skills repository's `main` branch.
6. In the Nix repository, update the pinned source revision:

   ```bash
   nix flake update personal-skills
   ```

7. Verify and build the configuration:

   ```bash
   devenv tasks run check:lint
   devenv tasks run test:eval
   ```

8. Switch the target machine to deploy the new revision.
9. Run `find ~/.agents/skills -name SKILL.md -print` to list installed skills.

The Nix flake lock pins the revision. Do not edit `flake.lock` by hand. For
source structure and authoring rules, see the [skills repository](https://github.com/funkymonkeymonk/skills).
