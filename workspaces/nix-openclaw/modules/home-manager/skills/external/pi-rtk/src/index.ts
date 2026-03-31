/**
 * Pi RTK Extension
 *
 * Integrates RTK (Rust Token Killer) with Pi coding agent to reduce
 * LLM token consumption by 60-90% on common dev commands.
 *
 * RTK: https://github.com/rtk-ai/rtk
 *
 * This extension intercepts bash tool calls and rewrites them to use
 * rtk equivalents, delivering compressed output to the LLM.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

// Commands that RTK supports for rewriting
// See: https://github.com/rtk-ai/rtk#commands-rewritten
const RTK_SUPPORTED_PATTERNS = [
  // Git
  /^git\s+(status|diff|log|add|commit|push|pull|show)/,
  // GitHub CLI
  /^gh\s+(pr|issue|run)/,
  // File operations
  /^(cat|head|tail|ls|find|grep|rg)\s+/,
  // Build tools
  /^(cargo|npm|pnpm|yarn|make|cmake)\s+/,
  // Test runners
  /^(vitest|jest|pytest|playwright)\s+/,
  // Linters
  /^(eslint|biome|ruff|golangci-lint|rubocop)\s+/,
  // Containers
  /^(docker|kubectl)\s+/,
  // Package managers
  /^(pip|bundle|prisma)\s+/,
  // TypeScript
  /^tsc/,
  // Prettier
  /^prettier/,
];

// Check if a command should be rewritten
function shouldRewrite(command: string): boolean {
  const trimmed = command.trim();

  // Skip if already using rtk
  if (trimmed.startsWith("rtk ")) {
    return false;
  }

  // Skip if RTK_DISABLED is set
  if (process.env.RTK_DISABLED === "1") {
    return false;
  }

  // Check against supported patterns
  return RTK_SUPPORTED_PATTERNS.some((pattern) => pattern.test(trimmed));
}

// Call rtk rewrite to transform the command
async function rtkRewrite(command: string): Promise<string | null> {
  try {
    const { stdout } = await execAsync(`rtk rewrite ${JSON.stringify(command)}`, {
      timeout: 5000,
      encoding: "utf-8",
    });

    const rewritten = stdout.trim();

    // If rtk returns the same command, no rewrite needed
    if (rewritten === command) {
      return null;
    }

    return rewritten;
  } catch (error) {
    // rtk rewrite returns non-zero if no rewrite applies
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  // Intercept bash tool calls and rewrite them
  pi.on("tool_call", async (event) => {
    // Only process bash tool calls
    if (event.toolName !== "bash") {
      return;
    }

    const command = event.input.command;
    if (!command) {
      return;
    }

    // Check if this command should be rewritten
    if (!shouldRewrite(command)) {
      return;
    }

    // Try to rewrite the command
    const rewritten = await rtkRewrite(command);
    if (rewritten) {
      // Mutate the command in place
      event.input.command = rewritten;
    }
  });

  // Register a command to check rtk status
  pi.registerCommand("rtk-status", {
    description: "Show RTK status and token savings",
    handler: async (_args, ctx) => {
      try {
        const { stdout } = await execAsync("rtk gain", { encoding: "utf-8" });
        ctx.ui.notify(stdout.trim(), "info");
      } catch (error) {
        ctx.ui.notify(
          "RTK not available. Install from https://github.com/rtk-ai/rtk",
          "error"
        );
      }
    },
  });

  // Register a command to discover missed savings
  pi.registerCommand("rtk-discover", {
    description: "Find missed RTK savings opportunities",
    handler: async (_args, ctx) => {
      try {
        const { stdout } = await execAsync("rtk discover", { encoding: "utf-8" });
        ctx.ui.notify(stdout.trim(), "info");
      } catch (error) {
        ctx.ui.notify("RTK discover failed. Is rtk installed?", "error");
      }
    },
  });
}
