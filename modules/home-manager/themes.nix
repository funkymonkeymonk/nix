# Unified Earthsong theme definitions for all configured tools.
#
# This file is the single source of truth for the Earthsong color palette and
# exports per-tool theme configurations that are consumed by other home-manager
# modules.  Adding a new tool means adding one attribute here, not scattering
# colour values across multiple files.
#
# Palette source: Ghostty built-in theme "Earthsong"
# (Applications/Ghostty.app/Contents/Resources/ghostty/themes/Earthsong)
{
  lib,
  pkgs,
  ...
}: let
  # ---------------------------------------------------------------------------
  # Canonical Earthsong palette
  # ---------------------------------------------------------------------------
  p = {
    # ANSI normal colours
    black = "#121418"; # 0
    red = "#c94234"; # 1
    green = "#85c54c"; # 2
    yellow = "#f5ae2e"; # 3
    blue = "#1398b9"; # 4
    magenta = "#d0633d"; # 5  (warm orange-red)
    cyan = "#509552"; # 6
    white = "#e5c6aa"; # 7

    # ANSI bright colours
    brightBlack = "#675f54"; # 8
    brightRed = "#ff645a"; # 9
    brightGreen = "#98e036"; # 10
    brightYellow = "#e0d561"; # 11
    brightBlue = "#5fdaff"; # 12
    brightMagenta = "#ff9269"; # 13
    brightCyan = "#84f088"; # 14
    brightWhite = "#f6f7ec"; # 15

    # Special
    bg = "#292520";
    fg = "#e5c7a9";
    cursor = "#f6f7ec";
    cursorText = "#292520";
    selectionBg = "#121418";
    selectionFg = "#e5c7a9";

    # Derived semantic aliases used below
    comment = "#675f54"; # brightBlack – muted
    selection = "#3d3530"; # slightly lighter than bg for selections
    lineHighlight = "#322d28"; # subtle current-line highlight
    border = "#3d3530"; # UI borders/frames
    statusBg = "#1e1a17"; # darker bg for status bars
  };

  # ---------------------------------------------------------------------------
  # Helper: strip the leading '#' for tools that want bare hex
  # ---------------------------------------------------------------------------
  bare = hex: lib.removePrefix "#" hex;

  # ---------------------------------------------------------------------------
  # Per-tool theme derivations
  # ---------------------------------------------------------------------------

  # -- bat ---------------------------------------------------------------
  # bat supports .tmTheme (TextMate) or .sublime-color-scheme files placed in
  # $(bat --config-dir)/themes/.  We generate a minimal .tmTheme XML that maps
  # the Earthsong palette onto the standard TextMate scopes.
  batThemeFile = pkgs.writeText "Earthsong.tmTheme" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>Earthsong</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key><string>${p.bg}</string>
            <key>foreground</key><string>${p.fg}</string>
            <key>caret</key><string>${p.cursor}</string>
            <key>selection</key><string>${p.selectionBg}</string>
            <key>lineHighlight</key><string>${p.lineHighlight}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>comment, punctuation.definition.comment</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.comment}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>string, string.quoted</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.yellow}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>keyword, keyword.control, storage</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.blue}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>keyword.operator</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.brightMagenta}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>entity.name.function, support.function</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.brightGreen}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>entity.name.type, entity.name.class, support.type, support.class</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.brightBlue}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>variable, variable.other</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.fg}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>constant.numeric, constant.language, constant.character</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.magenta}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>markup.inserted, diff.inserted</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.green}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>markup.deleted, diff.deleted</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.red}</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>markup.changed, diff.changed</string>
          <key>settings</key><dict>
            <key>foreground</key><string>${p.yellow}</string>
          </dict>
        </dict>
      </array>
    </dict>
    </plist>
  '';

  # -- fzf ---------------------------------------------------------------
  # FZF_DEFAULT_OPTS color string: --color=<spec>
  fzfColors = lib.concatStringsSep "," [
    "bg:${p.bg}"
    "bg+:${p.selection}"
    "fg:${p.fg}"
    "fg+:${p.brightWhite}"
    "hl:${p.brightBlue}"
    "hl+:${p.brightBlue}"
    "border:${p.border}"
    "prompt:${p.yellow}"
    "pointer:${p.brightMagenta}"
    "marker:${p.green}"
    "spinner:${p.cyan}"
    "info:${p.comment}"
    "header:${p.blue}"
  ];

  # -- helix -------------------------------------------------------------
  # Written to ~/.config/helix/themes/earthsong.toml.
  helixTheme = ''
    # Earthsong theme for Helix
    # Generated from the canonical Earthsong palette.

    "attribute"           = { fg = "${p.brightMagenta}" }
    "comment"             = { fg = "${p.comment}", modifiers = ["italic"] }
    "constant"            = { fg = "${p.magenta}" }
    "constant.numeric"    = { fg = "${p.magenta}" }
    "constant.character"  = { fg = "${p.yellow}" }
    "constructor"         = { fg = "${p.brightBlue}" }
    "function"            = { fg = "${p.brightGreen}" }
    "function.builtin"    = { fg = "${p.brightGreen}" }
    "function.macro"      = { fg = "${p.brightGreen}" }
    "keyword"             = { fg = "${p.blue}" }
    "keyword.control"     = { fg = "${p.blue}", modifiers = ["bold"] }
    "keyword.operator"    = { fg = "${p.brightMagenta}" }
    "label"               = { fg = "${p.blue}" }
    "namespace"           = { fg = "${p.brightBlue}" }
    "operator"            = { fg = "${p.brightMagenta}" }
    "punctuation"         = { fg = "${p.white}" }
    "string"              = { fg = "${p.yellow}" }
    "string.regexp"       = { fg = "${p.brightYellow}" }
    "tag"                 = { fg = "${p.blue}" }
    "type"                = { fg = "${p.brightBlue}" }
    "type.builtin"        = { fg = "${p.brightBlue}" }
    "variable"            = { fg = "${p.fg}" }
    "variable.builtin"    = { fg = "${p.brightBlue}" }
    "variable.parameter"  = { fg = "${p.fg}" }

    "markup.heading"   = { fg = "${p.yellow}", modifiers = ["bold"] }
    "markup.bold"      = { modifiers = ["bold"] }
    "markup.italic"    = { modifiers = ["italic"] }
    "markup.link.text" = { fg = "${p.brightBlue}", modifiers = ["underlined"] }
    "markup.link.url"  = { fg = "${p.cyan}", modifiers = ["underlined"] }
    "markup.raw"       = { fg = "${p.brightGreen}" }
    "markup.quote"     = { fg = "${p.comment}", modifiers = ["italic"] }

    "diff.plus"  = { fg = "${p.green}" }
    "diff.minus" = { fg = "${p.red}" }
    "diff.delta" = { fg = "${p.yellow}" }

    "ui.background"          = { fg = "${p.fg}", bg = "${p.bg}" }
    "ui.cursor"              = { fg = "${p.cursorText}", bg = "${p.cursor}" }
    "ui.cursor.primary"      = { fg = "${p.cursorText}", bg = "${p.cursor}" }
    "ui.cursor.match"        = { bg = "${p.selection}" }
    "ui.selection"           = { bg = "${p.selection}" }
    "ui.selection.primary"   = { bg = "${p.selectionBg}" }
    "ui.linenr"              = { fg = "${p.comment}" }
    "ui.linenr.selected"     = { fg = "${p.brightWhite}" }
    "ui.cursorline.primary"  = { bg = "${p.lineHighlight}" }
    "ui.statusline"          = { fg = "${p.fg}", bg = "${p.statusBg}" }
    "ui.statusline.inactive" = { fg = "${p.comment}", bg = "${p.statusBg}" }
    "ui.statusline.insert"   = { fg = "${p.bg}", bg = "${p.green}" }
    "ui.statusline.select"   = { fg = "${p.bg}", bg = "${p.yellow}" }
    "ui.popup"               = { fg = "${p.fg}", bg = "${p.statusBg}" }
    "ui.menu"                = { fg = "${p.fg}", bg = "${p.statusBg}" }
    "ui.menu.selected"       = { fg = "${p.brightWhite}", bg = "${p.selectionBg}" }
    "ui.help"                = { fg = "${p.fg}", bg = "${p.statusBg}" }
    "ui.text"                = { fg = "${p.fg}" }
    "ui.text.focus"          = { fg = "${p.brightWhite}" }
    "ui.virtual.ruler"       = { bg = "${p.lineHighlight}" }
    "ui.virtual.indent-guide" = { fg = "${p.border}" }
    "ui.virtual.inlay-hint"  = { fg = "${p.comment}" }
    "ui.window"              = { bg = "${p.statusBg}" }

    "warning"            = { fg = "${p.yellow}" }
    "error"              = { fg = "${p.red}" }
    "info"               = { fg = "${p.brightBlue}" }
    "hint"               = { fg = "${p.comment}" }
    "diagnostic.error".underline   = { color = "${p.red}", style = "curl" }
    "diagnostic.warning".underline = { color = "${p.yellow}", style = "curl" }

    [palette]
    bg             = "${p.bg}"
    fg             = "${p.fg}"
    black          = "${p.black}"
    red            = "${p.red}"
    green          = "${p.green}"
    yellow         = "${p.yellow}"
    blue           = "${p.blue}"
    magenta        = "${p.magenta}"
    cyan           = "${p.cyan}"
    white          = "${p.white}"
    bright_black   = "${p.brightBlack}"
    bright_red     = "${p.brightRed}"
    bright_green   = "${p.brightGreen}"
    bright_yellow  = "${p.brightYellow}"
    bright_blue    = "${p.brightBlue}"
    bright_magenta = "${p.brightMagenta}"
    bright_cyan    = "${p.brightCyan}"
    bright_white   = "${p.brightWhite}"
    cursor         = "${p.cursor}"
    comment        = "${p.comment}"
    selection      = "${p.selection}"
    border         = "${p.border}"
    status_bg      = "${p.statusBg}"
  '';

  # -- glamour (glow) ----------------------------------------------------
  # Glamour accepts a JSON stylesheet path as the glow "style" value.
  # We generate the JSON and expose the store path so charm.nix can reference it.
  glamourStyle = pkgs.writeText "earthsong-glamour.json" (builtins.toJSON {
    document = {
      block_prefix = "\n";
      block_suffix = "\n";
      color = bare p.fg;
      margin = 2;
    };
    block_quote = {
      indent = 1;
      indent_token = "│ ";
      color = bare p.comment;
    };
    paragraph = {};
    list = {level_indent = 2;};
    heading = {
      block_suffix = "\n";
      color = bare p.yellow;
      bold = true;
    };
    h1 = {
      prefix = " ";
      suffix = " ";
      color = bare p.brightWhite;
      background_color = bare p.selectionBg;
      bold = true;
    };
    h2 = {prefix = "## ";};
    h3 = {prefix = "### ";};
    h4 = {prefix = "#### ";};
    h5 = {prefix = "##### ";};
    h6 = {
      prefix = "###### ";
      color = bare p.comment;
      bold = false;
    };
    text = {};
    strikethrough = {crossed_out = true;};
    emph = {italic = true;};
    strong = {bold = true;};
    hr = {
      color = bare p.border;
      format = "\n--------\n";
    };
    item = {block_prefix = "• ";};
    enumeration = {block_prefix = ". ";};
    task = {
      ticked = "[✓] ";
      unticked = "[ ] ";
    };
    link = {
      color = bare p.brightBlue;
      underline = true;
    };
    link_text = {
      color = bare p.cyan;
      bold = true;
    };
    image = {
      color = bare p.brightMagenta;
      underline = true;
    };
    image_text = {
      color = bare p.comment;
      format = "Image: {{.text}} →";
    };
    code = {
      prefix = " ";
      suffix = " ";
      color = bare p.brightGreen;
      background_color = bare p.lineHighlight;
    };
    code_block = {
      color = bare p.fg;
      margin = 2;
      chroma = {
        text = {color = bare p.fg;};
        error = {
          color = bare p.brightWhite;
          background_color = bare p.red;
        };
        comment = {color = bare p.comment;};
        comment_preproc = {color = bare p.brightMagenta;};
        keyword = {color = bare p.blue;};
        keyword_reserved = {color = bare p.brightBlue;};
        keyword_namespace = {color = bare p.brightBlue;};
        keyword_type = {color = bare p.brightBlue;};
        operator = {color = bare p.brightMagenta;};
        punctuation = {color = bare p.white;};
        name = {color = bare p.fg;};
        name_builtin = {color = bare p.brightMagenta;};
        name_tag = {color = bare p.blue;};
        name_attribute = {color = bare p.brightBlue;};
        name_class = {
          color = bare p.brightWhite;
          underline = true;
          bold = true;
        };
        name_function = {color = bare p.brightGreen;};
        literal_number = {color = bare p.magenta;};
        literal_string = {color = bare p.yellow;};
        literal_string_escape = {color = bare p.brightYellow;};
        generic_deleted = {color = bare p.red;};
        generic_emph = {italic = true;};
        generic_inserted = {color = bare p.green;};
        generic_strong = {bold = true;};
        generic_subheading = {color = bare p.comment;};
        background = {background_color = bare p.bg;};
      };
    };
    table = {};
    definition_list = {};
    definition_term = {};
    definition_description = {block_prefix = "\n🠶 ";};
    html_block = {};
    html_span = {};
  });

  # -- zellij ------------------------------------------------------------
  # KDL theme block written to ~/.config/zellij/themes/earthsong.kdl.
  # Uses the new component-based API (Zellij ≥ 0.40).
  zellijTheme = ''
    themes {
        earthsong {
            text_unselected {
                base #${bare p.fg}
                background #${bare p.bg}
                emphasis_0 #${bare p.blue}
                emphasis_1 #${bare p.yellow}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            text_selected {
                base #${bare p.brightWhite}
                background #${bare p.selectionBg}
                emphasis_0 #${bare p.brightBlue}
                emphasis_1 #${bare p.brightYellow}
                emphasis_2 #${bare p.brightGreen}
                emphasis_3 #${bare p.brightMagenta}
            }
            ribbon_unselected {
                base #${bare p.fg}
                background #${bare p.statusBg}
                emphasis_0 #${bare p.blue}
                emphasis_1 #${bare p.yellow}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            ribbon_selected {
                base #${bare p.bg}
                background #${bare p.yellow}
                emphasis_0 #${bare p.bg}
                emphasis_1 #${bare p.red}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            table_title {
                base #${bare p.brightWhite}
                background #${bare p.statusBg}
                emphasis_0 #${bare p.yellow}
                emphasis_1 #${bare p.blue}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            table_cell_unselected {
                base #${bare p.fg}
                background #${bare p.bg}
                emphasis_0 #${bare p.blue}
                emphasis_1 #${bare p.yellow}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            table_cell_selected {
                base #${bare p.brightWhite}
                background #${bare p.selection}
                emphasis_0 #${bare p.brightBlue}
                emphasis_1 #${bare p.brightYellow}
                emphasis_2 #${bare p.brightGreen}
                emphasis_3 #${bare p.brightMagenta}
            }
            list_unselected {
                base #${bare p.fg}
                background #${bare p.bg}
                emphasis_0 #${bare p.blue}
                emphasis_1 #${bare p.yellow}
                emphasis_2 #${bare p.green}
                emphasis_3 #${bare p.magenta}
            }
            list_selected {
                base #${bare p.brightWhite}
                background #${bare p.selection}
                emphasis_0 #${bare p.brightBlue}
                emphasis_1 #${bare p.brightYellow}
                emphasis_2 #${bare p.brightGreen}
                emphasis_3 #${bare p.brightMagenta}
            }
            frame_unselected {
                base #${bare p.border}
                background #${bare p.bg}
                emphasis_0 #${bare p.comment}
                emphasis_1 #${bare p.comment}
                emphasis_2 #${bare p.comment}
                emphasis_3 #${bare p.comment}
            }
            frame_selected {
                base #${bare p.yellow}
                background #${bare p.bg}
                emphasis_0 #${bare p.brightYellow}
                emphasis_1 #${bare p.brightYellow}
                emphasis_2 #${bare p.brightYellow}
                emphasis_3 #${bare p.brightYellow}
            }
            frame_highlight {
                base #${bare p.brightMagenta}
                background #${bare p.bg}
                emphasis_0 #${bare p.brightMagenta}
                emphasis_1 #${bare p.brightMagenta}
                emphasis_2 #${bare p.brightMagenta}
                emphasis_3 #${bare p.brightMagenta}
            }
            exit_code_success {
                base #${bare p.green}
                background #${bare p.bg}
                emphasis_0 #${bare p.brightGreen}
                emphasis_1 #${bare p.brightGreen}
                emphasis_2 #${bare p.brightGreen}
                emphasis_3 #${bare p.brightGreen}
            }
            exit_code_error {
                base #${bare p.red}
                background #${bare p.bg}
                emphasis_0 #${bare p.brightRed}
                emphasis_1 #${bare p.brightRed}
                emphasis_2 #${bare p.brightRed}
                emphasis_3 #${bare p.brightRed}
            }
            multiplayer_user_colors {
                player_1 #${bare p.brightBlue}
                player_2 #${bare p.brightGreen}
                player_3 #${bare p.brightMagenta}
                player_4 #${bare p.yellow}
                player_5 #${bare p.cyan}
                player_6 #${bare p.magenta}
            }
        }
    }
  '';

  # -- jj color-words ----------------------------------------------------
  # Passed to programs.jujutsu.settings.colors.
  # Line-level colors are intentionally dark (barely above bg) so long runs
  # of additions/removals don't overwhelm. Token colors pop with bright
  # Earthsong accents + saturated backgrounds.
  jjColors = {
    "diff context" = {fg = p.brightBlack;};
    "diff removed" = {
      fg = "#6b2e2a";
      bg = "#110806";
    };
    "diff added" = {
      fg = "#2e5218";
      bg = "#070f04";
    };
    "diff removed token" = {
      fg = p.brightRed;
      bg = "#5c1a14";
      underline = false;
    };
    "diff added token" = {
      fg = p.brightGreen;
      bg = "#1a3d0a";
      underline = false;
    };
  };

  # -- sketchybar --------------------------------------------------------
  # Color and font configuration for the sketchybar macOS status bar.
  # Colors are mapped from the Earthsong palette; fonts use system SF faces.
  sketchybarTheme = {
    colors = {
      inherit (p) black white red green blue yellow;
      orange = p.magenta; # closest warm hue in Earthsong
      magenta = p.brightMagenta;
      grey = p.brightBlack;
      bar = {
        bg = p.statusBg;
        inherit (p) border;
      };
      popup = {
        bg = p.statusBg;
        inherit (p) border;
      };
      bg1 = p.selection;
      bg2 = p.border;
    };
    font = {
      text = "SF Pro";
      numbers = "SF Mono";
    };
  };
in {
  # Export all derivations as module arguments so sibling modules can import them.
  _module.args.earthsong = {
    inherit
      p
      batThemeFile
      fzfColors
      helixTheme
      glamourStyle
      zellijTheme
      jjColors
      sketchybarTheme
      ;
  };
}
