{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.opencode;
  roleConfigs = cfg.roles or [];

  # Base opencode configuration (always present)
  baseConfig = {
    "$schema" = "https://opencode.ai/config.json";
    inherit (cfg) theme model autoupdate;
    mcp = {
      devenv = {
        type = "local";
        command = ["devenv" "mcp"];
        enabled = true;
      };
    };
    permission = {
      bash = {
        "task *" = "allow";
        "npx *" = "allow";
        "npm *" = "allow";
      };
    };
    tools = {
      devenv = true;
    };
  };

  # Merge all role configs
  roleConfig = foldl' (acc: roleCfg: recursiveUpdate acc roleCfg) {} roleConfigs;

  mergedWithRoles = recursiveUpdate baseConfig roleConfig;

  # Browser agents configuration (only when enabled)
  browserAgentsConfig = mkIf cfg.enableBrowserAgents {
    mcp = {
      chrome-devtools = {
        type = "local";
        command = ["npx" "-y" "chrome-devtools-mcp@latest"];
        enabled = true;
      };
      puppeteer-mcp = {
        type = "local";
        command = ["npx" "-y" "puppeteer-mcp-server"];
        enabled = true;
      };
    };
    agent = {
      browser-research = {
        description = "Agent for browser-based research tasks";
        prompt = "You are a research assistant with browser automation capabilities. Use headless browsers for background research, visible browsers only when human interaction is needed. Prioritize efficiency and minimal browser windows.";
        mcp = {
          chrome-devtools = true;
          puppeteer-mcp = true;
        };
      };
      browser-debug = {
        description = "Agent for debugging web applications";
        prompt = "You are a web debugging assistant. Connect to existing browser instances when possible. Use Chrome DevTools MCP for performance analysis and debugging. Take screenshots and analyze network requests.";
        mcp = {
          chrome-devtools = true;
          puppeteer-mcp = true;
        };
      };
      browser-test = {
        description = "Agent for automated browser testing";
        prompt = "You are a browser testing specialist. Use Puppeteer MCP for form interactions, element clicking, and automated workflows. Create headless browsers for background testing.";
        mcp = {
          chrome-devtools = true;
          puppeteer-mcp = true;
        };
      };
    };
    permission = {
      bash = {
        "chrome *" = "allow";
        "vivaldi *" = "allow";
      };
    };
    tools = {
      chrome-devtools = true;
      puppeteer-mcp = true;
    };
  };

  # Merge base config with browser agents if enabled
  finalConfig =
    if cfg.enableBrowserAgents
    then
      lib.recursiveUpdate mergedWithRoles {
        mcp = {
          inherit (mergedWithRoles.mcp) devenv;
          inherit (browserAgentsConfig.mcp) chrome-devtools puppeteer-mcp;
        };
        inherit (browserAgentsConfig) agent;
        permission = {
          bash = mergedWithRoles.permission.bash // browserAgentsConfig.permission.bash;
        };
        tools = mergedWithRoles.tools // browserAgentsConfig.tools;
      }
    else mergedWithRoles;
in {
  config = mkIf cfg.enable {
    home.file.".config/opencode/opencode.json" = {
      text = builtins.toJSON finalConfig;
    };
  };
}
