# Global OpenCode Rules

## Language & Communication

- **Always respond in English** regardless of user input language
- Write all documentation, code comments, and explanations in English

## Version Control (jj)

Repositories use Jujutsu (jj) for version control. Follow this discipline on every turn:

1. **Start of turn** — run `jj status` first.
   - If the working copy has uncommitted changes with no description, review them and `jj describe -m "..."` before proceeding.
   - If the working copy is empty (no description set), proceed — you're already on a clean slate.

2. **During the turn** — make changes freely. The working copy is always a commit in jj.

3. **End of turn** — if any changes were made:
   - `jj describe -m "<conventional-commit message>"` to name the commit.
   - `jj new` to leave an empty commit ready for the next turn.

4. **Never push** unless the user explicitly asks.
