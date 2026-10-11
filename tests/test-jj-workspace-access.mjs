import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  existsSync,
  mkdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { delimiter, join } from "node:path";
import { tmpdir } from "node:os";
import test from "node:test";

const pluginPath = process.env.JJ_WORKSPACE_PLUGIN;
assert.ok(pluginPath, "JJ_WORKSPACE_PLUGIN must point to the plugin under test");

const runner = `
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const { default: jjWorkspaceAccess } = await import(pathToFileURL(process.env.JJ_WORKSPACE_PLUGIN));
const config = JSON.parse(process.env.JJ_CONFIG_JSON);
const hooks = await jjWorkspaceAccess({ directory: process.env.JJ_PROJECT });
await hooks.config(config);
const jj = JSON.parse(readFileSync(process.env.JJ_ARGV_LOG, "utf8"));
process.stdout.write(JSON.stringify({
  config,
  args: jj.args,
  cwd: jj.cwd,
}));
`;

function listing(paths) {
  return paths.map((path) => JSON.stringify(path)).join("\n");
}

function invokePlugin({ setup, jjExit = false }) {
  const tempRoot = mkdtempSync(join(tmpdir(), "jj-workspace-access-test-"));
  try {
    const home = join(tempRoot, "home");
    const workspaces = join(home, "workspaces");
    const project = join(tempRoot, "repo");
    const bin = join(tempRoot, "bin");
    const argvLog = join(tempRoot, "jj-argv.json");
    mkdirSync(workspaces, { recursive: true });
    mkdirSync(project);
    mkdirSync(bin);
    const realWorkspaces = realpathSync(workspaces);
    const { roots, permission } = setup({tempRoot, workspaces: realWorkspaces});
    for (const root of roots) {
      if (!existsSync(root)) mkdirSync(root, {recursive: true});
    }

    writeFileSync(
      join(bin, "jj"),
      `#!${process.execPath}
const { writeFileSync } = require("node:fs");
writeFileSync(process.env.JJ_ARGV_LOG, JSON.stringify({
  args: process.argv.slice(2),
  cwd: process.cwd(),
}));
if (process.env.JJ_WORKSPACE_LIST_EXIT === "1") process.exit(1);
process.stdout.write(process.env.JJ_WORKSPACE_LIST_OUTPUT ?? "");
`,
      { mode: 0o755 },
    );

    const result = spawnSync(process.execPath, ["--input-type=module", "-e", runner], {
      encoding: "utf8",
      env: {
        ...process.env,
        HOME: home,
        PATH: `${bin}${delimiter}${process.env.PATH}`,
        JJ_ARGV_LOG: argvLog,
        JJ_CONFIG_JSON: JSON.stringify({ permission }),
        JJ_PROJECT: project,
        JJ_WORKSPACE_LIST_OUTPUT: listing(roots),
        ...(jjExit ? { JJ_WORKSPACE_LIST_EXIT: "1" } : { JJ_WORKSPACE_LIST_EXIT: "0" }),
        JJ_WORKSPACE_PLUGIN: pluginPath,
      },
    });
    assert.equal(result.status, 0, result.stderr || result.error?.message);
    return {
      ...JSON.parse(result.stdout),
      project: realpathSync(project),
      workspaces: realWorkspaces,
    };
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
}

test("grants access only to this jj repo's workspaces under ~/workspaces", () => {
  const result = invokePlugin({
    setup: ({tempRoot, workspaces}) => ({
      roots: [
        join(workspaces, "feature"),
        join(tempRoot, "unrelated-repo"),
        `${workspaces}-other/feature`,
      ],
      permission: { external_directory: {} },
    }),
  });
  const {config, args, cwd, project, workspaces} = result;
  const allowed = join(workspaces, "feature");

  assert.equal(cwd, project, "jj workspace discovery must run in the current session repo");
  assert.deepEqual(args.slice(0, 5), [
    "workspace",
    "list",
    "--ignore-working-copy",
    "--no-pager",
    "--color=never",
  ]);
  assert.equal(args[5], "--template");
  assert.equal(args[6], 'if(root, json(root) ++ "\\n")');
  assert.deepEqual(config.permission.external_directory, {
    [allowed]: "allow",
    [`${allowed}/**`]: "allow",
  });
});

test("leaves permissions unchanged when the project is not a jj repo", () => {
  const permission = {
    bash: { "git status": "allow" },
    external_directory: { "*": "ask", "/private/**": "deny" },
  };
  const { config } = invokePlugin({
    setup: () => ({permission, roots: []}),
    jjExit: true,
  });

  assert.deepEqual(config.permission, permission);
});

test("does not grant access to a workspace symlink that resolves outside ~/workspaces", () => {
  const { config } = invokePlugin({
    setup: ({tempRoot, workspaces}) => {
      const outside = join(tempRoot, "outside-workspace");
      const symlinkedWorkspace = join(workspaces, "linked-workspace");
      mkdirSync(outside);
      symlinkSync(outside, symlinkedWorkspace);
      return {
        roots: [symlinkedWorkspace],
        permission: { external_directory: {} },
      };
    },
  });

  assert.deepEqual(config.permission.external_directory, {});
});

test("does not create broad grants for workspace paths containing permission wildcards", () => {
  const { config } = invokePlugin({
    setup: ({workspaces}) => ({
      roots: [join(workspaces, "feature*"), join(workspaces, "feature?")],
      permission: { external_directory: {} },
    }),
  });

  assert.deepEqual(config.permission.external_directory, {});
});

test("merges workspace grants without dropping existing rules or explicit denials", () => {
  const result = invokePlugin({
    setup: ({workspaces}) => {
      const allowed = join(workspaces, "feature");
      const deniedWorkspace = join(workspaces, "blocked");
      return {
        roots: [allowed, deniedWorkspace],
        permission: {
          bash: { "jj status": "allow" },
          external_directory: {
            "/existing/**": "allow",
            [deniedWorkspace]: "deny",
            [`${allowed}/secrets/**`]: "deny",
          },
        },
      };
    },
  });
  const {config, workspaces} = result;
  const allowed = join(workspaces, "feature");
  const deniedWorkspace = join(workspaces, "blocked");
  const permission = {
    bash: { "jj status": "allow" },
  };

  assert.deepEqual(config.permission, {
    bash: permission.bash,
    external_directory: {
      "/existing/**": "allow",
      [allowed]: "allow",
      [`${allowed}/**`]: "allow",
      [`${allowed}/secrets/**`]: "deny",
      [`${deniedWorkspace}/**`]: "allow",
      [deniedWorkspace]: "deny",
    },
  });
});

test("keeps workspace-scoped ask rules after generated grants", () => {
  const result = invokePlugin({
    setup: ({workspaces}) => {
      const allowed = join(workspaces, "feature");
      return {
        roots: [allowed],
        permission: {
          external_directory: {
            "*": "ask",
            [`${allowed}/secrets/**`]: "ask",
            "~/workspaces/feature/secrets/**": "ask",
            "$HOME/workspaces/feature/private/**": "ask",
          },
        },
      };
    },
  });
  const {config, workspaces} = result;
  const allowed = join(workspaces, "feature");
  const external = config.permission.external_directory;
  const ruleOrder = Object.keys(external);

  assert.equal(external["*"], "ask");
  assert.ok(ruleOrder.indexOf("*") < ruleOrder.indexOf(allowed));
  assert.equal(external[`${allowed}/secrets/**`], "ask");
  assert.ok(ruleOrder.indexOf(`${allowed}/secrets/**`) > ruleOrder.indexOf(`${allowed}/**`));
  assert.equal(external["~/workspaces/feature/secrets/**"], "ask");
  assert.ok(ruleOrder.indexOf("~/workspaces/feature/secrets/**") > ruleOrder.indexOf(`${allowed}/**`));
  assert.equal(external["$HOME/workspaces/feature/private/**"], "ask");
  assert.ok(ruleOrder.indexOf("$HOME/workspaces/feature/private/**") > ruleOrder.indexOf(`${allowed}/**`));
});

test("appends generated root grants after broad asks when the root key already exists", () => {
  const result = invokePlugin({
    setup: ({workspaces}) => {
      const allowed = join(workspaces, "feature");
      return {
        roots: [allowed],
        permission: {
          external_directory: {
            [allowed]: "allow",
            "*": "ask",
          },
        },
      };
    },
  });
  const {config, workspaces} = result;
  const allowed = join(workspaces, "feature");
  const external = config.permission.external_directory;
  const ruleOrder = Object.keys(external);

  assert.equal(external[allowed], "allow");
  assert.equal(external["*"], "ask");
  assert.ok(ruleOrder.indexOf("*") < ruleOrder.indexOf(allowed));
  assert.ok(ruleOrder.indexOf(allowed) < ruleOrder.indexOf(`${allowed}/**`));
});
