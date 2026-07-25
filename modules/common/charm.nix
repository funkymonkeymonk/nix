# myConfig.charm options — owned here, consumed by modules/home-manager/charm.nix
# (loaded conditionally via modules/common/users.nix).
{lib, ...}: {
  options.myConfig.charm = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Charm CLI tools configuration (glow markdown renderer, mods AI CLI)";
    };

    glow = {
      style = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = ''
          Glow rendering style. "auto" detects the terminal background and
          picks "dark" or "light". Can also be a path to a custom JSON
          stylesheet (see glamour style gallery).
        '';
      };

      width = lib.mkOption {
        type = lib.types.int;
        default = 140;
        description = "Word-wrap width for glow output (0 to disable wrapping)";
      };

      pager = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Display output in a pager (like less -r)";
      };

      mouse = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable mouse wheel support in TUI mode";
      };

      showLineNumbers = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Show line numbers in TUI mode";
      };

      preserveNewLines = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Preserve newlines in rendered output";
      };
    };

    mods = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable mods (AI on the command line) from Charm";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = ''
          Mods configuration written to $XDG_CONFIG_HOME/mods/mods.yml.
          See https://github.com/charmbracelet/mods for available options.
        '';
      };
    };
  };
}
