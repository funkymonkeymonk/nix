#!/usr/bin/env bash
# vivaldi-workspaces.sh — sketchybar helper for Vivaldi's internal Workspaces.
#
# Subcommands:
#   build-popup <parent_item>
#     Read Vivaldi's Preferences JSON, rebuild the popup children under
#     <parent_item>, and toggle the popup open.
#
#   switch <index> <name> <parent_item>
#     Switch Vivaldi to the workspace at 1-based <index>.
#       * index 1..9  -> send ctrl+shift+<index>    (matches Vivaldi's
#                       COMMAND_WORKSPACE_SWITCH_N defaults)
#       * index == 10 -> send ctrl+shift+0 (if user bound it) else Quick
#                       Commands fallback using <name>
#       * index >= 11 -> Quick Commands fallback: F2, type name, Enter
#     Then close the popup.
#
# Environment:
#   VW_PREFS_PATH  Overrides the path to Vivaldi's Preferences file.
#                  Defaults to Default profile under Application Support.
#   VW_PROFILE     Profile directory name (default "Default"). Ignored if
#                  VW_PREFS_PATH is set.
#
# Exit codes:
#   0 — success (including "no workspaces found, popup shows message row")
#   2 — bad invocation (missing args)
#   3 — Preferences file unreadable after retry

set -euo pipefail

profile="${VW_PROFILE:-Default}"
prefs="${VW_PREFS_PATH:-$HOME/Library/Application Support/Vivaldi/$profile/Preferences}"

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") build-popup <parent_item>
  $(basename "$0") switch <index> <name> <parent_item>
EOF
  exit 2
}

# Read Preferences JSON with a single retry — Vivaldi occasionally rewrites
# the file and jq can see a mid-write empty/partial state.
read_prefs() {
  local out
  if out=$(jq -e '.vivaldi.workspaces.list' "$prefs" 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  sleep 0.15
  if out=$(jq -e '.vivaldi.workspaces.list' "$prefs" 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  return 1
}

# Emit TSV of "index<TAB>id<TAB>name" lines for each workspace. Indices are
# 1-based, matching Vivaldi's COMMAND_WORKSPACE_SWITCH_N numbering.
list_workspaces_tsv() {
  local list
  if ! list=$(read_prefs); then
    return 3
  fi
  printf '%s\n' "$list" | jq -r '
    to_entries
    | map([.key + 1, .value.id, .value.name] | @tsv)
    | .[]
  '
}

# sketchybar command wrapper — uses $PATH so the consumer's nix-installed
# sketchybar is picked up.
sbar() {
  sketchybar "$@"
}

# Escape a string for use inside an AppleScript string literal.
applescript_escape() {
  # Backslash-escape backslashes and double quotes.
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Activate Vivaldi and send a keystroke via System Events.
# Requires Accessibility permission for the parent process (sketchybar's
# launchd agent on first use prompts the user).
#
# Args: $1 = key (e.g. "1"), $2 = modifiers (AppleScript list, e.g. "control down, shift down")
send_keystroke() {
  local key="$1"
  local mods="$2"
  /usr/bin/osascript <<APPLESCRIPT
tell application "Vivaldi" to activate
delay 0.05
tell application "System Events"
  keystroke "$key" using {$mods}
end tell
APPLESCRIPT
}

# Fallback: open Vivaldi's Quick Commands (F2 by default), type the
# workspace name, press Return.
quick_commands_switch() {
  local name="$1"
  local escaped
  escaped=$(applescript_escape "$name")
  /usr/bin/osascript <<APPLESCRIPT
tell application "Vivaldi" to activate
delay 0.08
tell application "System Events"
  -- F2 is Vivaldi's default Quick Commands shortcut. If the user has
  -- remapped it, they can edit this script or the option surface.
  key code 120
  delay 0.12
  keystroke "$escaped"
  delay 0.08
  key code 36 -- return
end tell
APPLESCRIPT
}

cmd_build_popup() {
  local parent="${1:-}"
  [[ -z $parent ]] && usage

  # Wipe existing popup children. We always recreate so renames and
  # reorderings in Vivaldi show up on the next click.
  sbar --query "$parent" >/dev/null 2>&1 || true
  # sketchybar has no "remove all children of X" command, so we track the
  # children we create by a naming convention: "<parent>.row.N". On each
  # build we remove any that might be stale (up to an upper bound) then
  # add fresh ones.
  local max_rows=50
  for ((i = 1; i <= max_rows; i++)); do
    sbar --remove "$parent.row.$i" >/dev/null 2>&1 || true
  done

  local rows
  if ! rows=$(list_workspaces_tsv 2>/dev/null); then
    # Couldn't read preferences — show a single error row.
    sbar --add item "$parent.row.1" popup."$parent" \
      --set "$parent.row.1" \
        label="(Vivaldi Preferences unreadable)" \
        label.color=0xffff5d5d \
        background.drawing=off \
      --set "$parent" popup.drawing=on >/dev/null
    return 0
  fi

  if [[ -z $rows ]]; then
    sbar --add item "$parent.row.1" popup."$parent" \
      --set "$parent.row.1" \
        label="(No Vivaldi workspaces defined)" \
        background.drawing=off \
      --set "$parent" popup.drawing=on >/dev/null
    return 0
  fi

  # Build one row per workspace. Rows are added in reverse order (last
  # workspace first) so that when the popup renders top-to-bottom the
  # lowest visible row is workspace 1 — giving a bottom-to-top appearance
  # that matches the item sitting at the bottom of a vertical bar.
  #
  # We pass self_path so the click handler stays Nix-store-referenced
  # rather than hardcoding the store path here.
  local self_path="${BASH_SOURCE[0]}"
  local idx _id name
  while IFS=$'\t' read -r idx _id name; do
    [[ -z $idx ]] && continue
    local row="$parent.row.$idx"
    sbar --add item "$row" popup."$parent" \
      --set "$row" \
        label="$idx.  $name" \
        label.align=left \
        label.padding_left=10 \
        label.padding_right=20 \
        background.drawing=off \
        click_script="'$self_path' switch '$idx' '$name' '$parent'" \
      >/dev/null
  done < <(tac <<<"$rows")

  sbar --set "$parent" popup.drawing=toggle >/dev/null
}

cmd_switch() {
  local idx="${1:-}"
  local name="${2:-}"
  local parent="${3:-}"
  [[ -z $idx || -z $name || -z $parent ]] && usage

  # Close popup immediately for responsiveness.
  sbar --set "$parent" popup.drawing=off >/dev/null 2>&1 || true

  if [[ $idx =~ ^[1-9]$ ]]; then
    # Workspaces 1-9: use Vivaldi's default ctrl+shift+<n> shortcut.
    send_keystroke "$idx" "control down, shift down"
  elif [[ $idx == "10" ]]; then
    # Vivaldi default for WORKSPACE_SWITCH_10 is unbound, so fall back
    # to Quick Commands by name. If the user has bound ctrl+shift+0,
    # they can override by renaming/reordering or extending this script.
    quick_commands_switch "$name"
  else
    # 11+: Quick Commands.
    quick_commands_switch "$name"
  fi
}

main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    build-popup) cmd_build_popup "$@" ;;
    switch)      cmd_switch "$@" ;;
    *)           usage ;;
  esac
}

main "$@"
