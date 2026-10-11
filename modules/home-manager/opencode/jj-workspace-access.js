import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join, sep } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

// Discover once per project initialization; do not snapshot or modify the jj repo.
export default async function JjWorkspaceAccess({ directory }) {
  return {
    config: async (config) => {
      if (config.permission === "deny" || config.permission === "allow") return;
      const permissions = typeof config.permission === "string"
        ? { "*": config.permission }
        : (config.permission ?? {});
      const external = permissions.external_directory;
      if (external === "deny" || external === "allow") return;

      let paths;
      let home;
      try {
        home = realpathSync(homedir());
        const prefix = realpathSync(join(home, "workspaces")) + sep;
        const { stdout } = await run("jj", [
          "workspace", "list", "--ignore-working-copy", "--no-pager",
          "--color=never", "--template", 'if(root, json(root) ++ "\\n")',
        ], { cwd: directory, timeout: 5000 });
        paths = stdout.trim().split("\n").filter(Boolean)
          .map((line) => JSON.parse(line))
          .filter((path) => typeof path === "string")
          .map((path) => {
            try {
              return realpathSync(path);
            } catch {
              return null;
            }
          })
          .filter((path) => path !== null && path.startsWith(prefix) && !/[?*]/.test(path));
      } catch {
        // Non-jj projects, unavailable jj, and discovery errors keep normal permissions.
        return;
      }
      if (paths.length === 0) return;

      const rules = typeof external === "string" ? { "*": external } : (external ?? {});
      const grants = Object.fromEntries(paths.flatMap((path) => [
        [path, "allow"], [path + "/**", "allow"],
      ]));
      // Last matching rule wins. Keep denials and workspace-scoped asks after grants.
      const preservedRules = Object.fromEntries(
        Object.entries(rules).filter(([rule, action]) =>
          action === "deny"
          || (action === "ask" && paths.some((path) => {
            let expanded = rule;
            if (rule === "~") expanded = home;
            else if (rule.startsWith(`~${sep}`)) expanded = join(home, rule.slice(2));
            else if (rule === "$HOME") expanded = home;
            else if (rule.startsWith(`$HOME${sep}`)) expanded = join(home, rule.slice(6));
            return expanded === path || expanded.startsWith(path + sep);
          }))
        ),
      );
      const merged = { ...rules };
      for (const path of Object.keys(grants)) delete merged[path];
      for (const path of Object.keys(preservedRules)) delete merged[path];
      config.permission = {
        ...permissions,
        external_directory: { ...merged, ...grants, ...preservedRules },
      };
    },
  };
}
