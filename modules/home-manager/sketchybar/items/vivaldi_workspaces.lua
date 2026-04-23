-- Vivaldi workspaces item.
--
-- Renders a single clickable item on the bar. On click, a helper shell
-- script reads Vivaldi's Preferences JSON, rebuilds the popup children,
-- and toggles the popup open. Row clicks call back into the same script
-- to switch workspaces.
--
-- The helper path is templated at Nix build time (see default.nix).
--
-- Active-workspace detection is intentionally not implemented — Vivaldi
-- does not expose that state to external processes. See README.md.

local colors = require("colors")

local parent_name = "vivaldi_workspaces"

sbar.add("item", parent_name, "@VW_POSITION@", {
  icon = {
    string = "@VW_ICON@",
    font = {
      style = "Bold",
      size = 14.0,
    },
    color = colors.white,
    padding_left = 10,
    padding_right = 8,
  },
  label = {
    string = "Workspaces",
    font = {
      style = "Semibold",
      size = 12.0,
    },
    color = colors.white,
    padding_left = 0,
    padding_right = 10,
  },
  background = {
    color = colors.bg1,
    border_color = colors.bg2,
    border_width = 1,
    corner_radius = 6,
    height = 28,
  },
  popup = {
    align = "center",
    height = 26,
  },
  -- On click: let the helper script parse Preferences and rebuild the
  -- popup. We deliberately re-read on every click so renames and
  -- additions inside Vivaldi show up without a sketchybar restart.
  click_script = "'@VW_SCRIPT@' build-popup " .. parent_name,
})
