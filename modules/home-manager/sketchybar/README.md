# Sketchybar Configuration Module

This module provides sketchybar configuration for macOS, with optional integration with the [zmre/aerospace-sketchybar-nix-lua-config](https://github.com/zmre/aerospace-sketchybar-nix-lua-config) flake.

## Overview

Sketchybar is a highly customizable macOS status bar replacement. This module provides:

- **Basic sketchybar setup** with customizable colors, fonts, and settings
- **Optional aerospace integration** for workspace display
- **Launchd service** to start sketchybar automatically
- **Integration with the zmre flake** for a complete Lua-based configuration

## Two Approaches

### Approach 1: Use the Built-in Module (Simple)

The built-in module provides basic sketchybar configuration with customization options:

```nix
{
  myConfig.sketchybar = {
    enable = true;
    height = 40;
    padding = 4;
    
    font = {
      text = "SF Pro";
      numbers = "SF Mono";
    };
    
    colors = {
      bar.bg = "#2c2e34";
      # ... see options.nix for all color options
    };
    
    useAerospaceIntegration = true;
  };
}
```

This creates the Lua config files (`colors.lua`, `settings.lua`, `bar.lua`, `default.lua`) but you'll need to provide your own `sketchybarrc` and item configurations.

### Approach 2: Use the zmre Flake (Complete)

For a complete, working configuration based on FelixKratz's dotfiles with aerospace integration:

```nix
# In your flake.nix inputs
{
  inputs = {
    aerospace-sketchybar.url = "github:zmre/aerospace-sketchybar-nix-lua-config";
  };
  
  outputs = { self, nix-darwin, home-manager, aerospace-sketchybar, ... }: {
    darwinConfigurations."my-mac" = nix-darwin.lib.darwinSystem {
      modules = [
        # ... your other modules
        
        # Option A: Use the package from the flake
        ({ pkgs, ... }: {
          homebrew.casks = [
            "font-sf-pro"
            "font-sf-mono-for-powerline"
            "sf-symbols"
          ];
          
          home-manager.users.youruser = {
            home.packages = [ aerospace-sketchybar.packages.aarch64-darwin.pwaerospace ];
            
            launchd.agents.aerospace-sketchybar = {
              enable = true;
              config = {
                Label = "com.zmre.aerospace-sketchy";
                ProgramArguments = [ 
                  "${aerospace-sketchybar.packages.aarch64-darwin.pwaerospace}/bin/pwaerospace" 
                ];
                RunAtLoad = true;
                KeepAlive = true;
              };
            };
          };
        })
      ];
    };
  };
}
```

The zmre flake provides:
- Pre-configured sketchybar with Lua items (workspaces, apple menu, calendar, widgets)
- Integrated aerospace configuration
- Jankyborders for window highlighting
- Helper binaries for CPU/memory monitoring
- App icons via sketchybar-app-font

## Required Fonts

Both approaches require these fonts:
- **SF Pro** - System font for text
- **SF Mono** or **SF Mono for Powerline** - For numbers and monospace text
- **SF Symbols** - For system icons
- **sketchybar-app-font** - For application icons (included via nix package)

Install via Homebrew:
```nix
homebrew.casks = [
  "font-sf-pro"
  "font-sf-mono-for-powerline"
  "sf-symbols"
];
```

## Integration with Aerospace

### If using the built-in module

The built-in module installs sketchybar and related tools but doesn't configure the aerospace.toml. You'll need to modify your aerospace config to trigger sketchybar events:

```toml
# In your aerospace.toml
after-startup-command = [
    'exec-and-forget sketchybar'
]

exec-on-workspace-change = ['/bin/bash', '-c',
  'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE PREV_WORKSPACE=$AEROSPACE_PREV_WORKSPACE'
]
```

### If using the zmre flake

The zmre flake bundles a complete aerospace.toml with all the necessary hooks. Use the `pwaerospace` package which includes:
- Modified aerospace binary with bundled config
- Pre-configured sketchybar
- Jankyborders
- All necessary environment variables

## Customization

### Colors

Colors can be customized via the `myConfig.sketchybar.colors` option:

| Option | Default | Description |
|--------|---------|-------------|
| `black` | `#181819` | Black color |
| `white` | `#e2e2e3` | White color |
| `red` | `#fc5d7c` | Red/accent color |
| `green` | `#9ed072` | Green color |
| `blue` | `#76cce0` | Blue color |
| `bar.bg` | `#2c2e34` | Bar background |
| `bar.border` | `#2c2e34` | Bar border |
| `bg1` | `#363944` | Item background |
| `bg2` | `#414550` | Secondary background |

### Bar Appearance

| Option | Default | Description |
|--------|---------|-------------|
| `height` | 40 | Bar height in pixels |
| `padding` | 2 | Left/right padding |
| `groupPadding` | 10 | Padding between groups |

## File Structure

```
modules/home-manager/sketchybar/
├── default.nix          # Main module - generates Lua configs
├── example.nix          # Example configuration
└── README.md           # This file
```

The module generates these config files in `~/.config/sketchybar/`:
- `colors.lua` - Color definitions from options
- `settings.lua` - Font and spacing settings
- `bar.lua` - Bar appearance
- `default.lua` - Default item styles
- `icons.lua` - Icon definitions (placeholder)

You'll need to provide:
- `sketchybarrc` - Main entry point
- `init.lua` - Item initialization
- `items/*.lua` - Individual bar items

See the [zmre repository](https://github.com/zmre/aerospace-sketchybar-nix-lua-config/tree/main/sbar-config-libs) for examples of these files.

## Credits

- [zmre](https://github.com/zmre) - aerospace-sketchybar-nix-lua-config flake
- [FelixKratz](https://github.com/FelixKratz) - SketchyBar and SbarLua
- [nikitabobko](https://github.com/nikitabobko) - Aerospace window manager

## Vivaldi Workspaces Dropdown

An optional item that renders a single clickable button on the bar. On
click, a helper script reads Vivaldi's `Preferences` JSON and opens a
popup listing your Vivaldi Workspaces. Clicking a row switches Vivaldi
to that workspace.

### Enable

```nix
myConfig.sketchybar = {
  enable = true;
  vivaldiWorkspaces = {
    enable = true;
    position = "right";  # or "left" / "center"
    profile = "Default"; # Vivaldi profile directory name
    iconText = "V";      # single character/glyph on the button
  };
};
```

### How it works

1. The button runs `sketchybar-vivaldi-workspaces build-popup <parent>`.
2. The script reads `~/Library/Application Support/Vivaldi/<profile>/Preferences`
   and extracts `vivaldi.workspaces.list` with `jq`. Renames/additions in
   Vivaldi show up on the next click — there is no caching.
3. Each workspace becomes a clickable popup row whose click handler
   calls back into the script as `switch <index> <name> <parent>`.
4. **Workspaces 1–9** switch via the built-in Vivaldi shortcut
   `⌃⇧1..9` (these are Vivaldi's `COMMAND_WORKSPACE_SWITCH_N` defaults).
5. **Workspaces 10+** fall back to Vivaldi's Quick Commands: the script
   presses `F2`, types the workspace name, presses Return.

### Required one-time setup

- **macOS Accessibility permission.** The click handlers send keystrokes
  via System Events. On first click, macOS will prompt you to allow
  `sketchybar` (or its parent process) in *System Settings → Privacy &
  Security → Accessibility*. This is a per-binary permission Nix cannot
  grant — you have to click allow once.

- **Vivaldi default shortcuts.** Verify `COMMAND_WORKSPACE_SWITCH_1..9`
  are bound to `⌃⇧1..9` in Vivaldi's *Settings → Keyboard → Workspaces*
  (they are by default). If you've remapped them, also update the
  keystroke in `scripts/vivaldi-workspaces.sh`.

- **Quick Commands shortcut.** Fallback path presses `F2`. If you've
  remapped Vivaldi's Quick Commands shortcut, edit the `key code 120`
  line in `scripts/vivaldi-workspaces.sh`.

### Limitations (important, read this)

- **Active workspace is not highlighted.** Vivaldi does not expose the
  currently active workspace to extensions, AppleScript, or any
  external process. The state lives only in Vivaldi's memory. A feature
  request exists upstream (Vivaldi forum post 877428) but has not been
  implemented. Every row in the popup looks the same — you don't get
  an "active" indicator.

- **No workspace-change events.** Since we can't detect the active
  workspace, we can't highlight on `aerospace_workspace_change`-style
  events either.

- **Preferences can be briefly unreadable.** Vivaldi occasionally
  rewrites `Preferences`. The script retries once after 150 ms. If
  both reads fail, the popup shows `(Vivaldi Preferences unreadable)`
  instead of crashing.

- **Profile support is single.** The `profile` option selects one
  Vivaldi profile directory. Multi-profile display would require extra
  logic not yet implemented.

### Future work

True active-workspace detection would require writing a Vivaldi Mod
(a JS file injected into Vivaldi's privileged `browser.html` UI) that
subscribes to the internal workspace store and pushes updates to
sketchybar via `sketchybar --trigger`. This works but breaks on
Vivaldi updates as internal APIs shift. See the "Awesome-Vivaldi"
community repo for prior art on Vivaldi Mods.
