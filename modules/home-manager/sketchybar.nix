{pkgs, ...}: {
  services.sketchybar = {
    enable = true;

    # Aerospace widget script
    config = ''
      # SketchyBar Configuration
      # -----------------------

      # Basic bar setup
      sketchybar --bar height=30 position=top margin=5 y_offset=0 drawing=on color=0xff1e1e2e

      # Global appearance
      sketchybar --default \
        icon.font="Hack Nerd Font:Bold:14.0" \
        label.font="Hack Nerd Font:Bold:14.0" \
        icon.color=0xffffffff \
        label.color=0xffffffff \
        padding_left=5 \
        padding_right=5 \
        label.padding_left=5 \
        label.padding_right=5 \
        background.padding_left=5 \
        background.padding_right=5 \
        background.corner_radius=8 \
        background.height=24

      # Aerospace workspace widget
      sketchybar --add item aerospace left \
        --set aerospace \
        icon="󰕰" \
        script="${pkgs.writeShellScript "aerospace-widget" ''
        update_aerospace() {
          local focused_workspace=$(aerospace list-workspaces --focused)
          local all_workspaces=$(aerospace list-workspaces --all)
          local workspace_count=$(echo "$all_workspaces" | wc -l | tr -d ' ')

          # Update the label using sketchybar command
          sketchybar --set aerospace label="$focused_workspace ($workspace_count)"
        }

        case "$1" in
          "update"|"")
            update_aerospace
            ;;
          *)
            # Cycle to next workspace on click
            local focused_workspace=$(aerospace list-workspaces --focused)
            local all_workspaces=$(aerospace list-workspaces --all)
            local next_workspace=$(echo "$all_workspaces" | grep -A1 "$focused_workspace" | tail -n1)

            # If we're at the last workspace, go to the first one
            if [ "$next_workspace" = "$focused_workspace" ] || [ -z "$next_workspace" ]; then
              next_workspace=$(echo "$all_workspaces" | head -n1)
            fi

            aerospace workspace "$next_workspace"
            update_aerospace
            ;;
        esac
      ''}" \
        update_freq=2 \
        label.drawing=on \
        on_click=true

      # Git repository widget
      sketchybar --add item git_repo right \
        --set git_repo \
        script="${pkgs.writeShellScript "git-widget" ''
        REPO_DIR="/Users/monkey/Projects/nix"

        update_git_status() {
          cd "$REPO_DIR" || return
          local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

          if [ "$current_branch" != "main" ]; then
            sketchybar --set git_repo label="Not on main"
            return
          fi

          if ! git rev-parse --verify origin/main >/dev/null 2>&1; then
            sketchybar --set git_repo label="No remote"
            return
          fi

          local behind_count=$(git rev-list --count origin/main..HEAD 2>/dev/null)
          if [ -z "$behind_count" ]; then
            behind_count=0
          fi

          if [ "$behind_count" -eq 0 ]; then
            sketchybar --set git_repo label="Up to date"
          else
            sketchybar --set git_repo label="$behind_count behind"
          fi
        }

        case "$1" in
          "update"|"")
            update_git_status
            ;;
          "click")
            cd "$REPO_DIR" || exit
            sketchybar --set git_repo label="Fetching..."
            git fetch --prune >/dev/null 2>&1
            update_git_status
            ;;
        esac
      ''}" \
        update_freq=30 \
        icon="󰘬" \
        label.drawing=on \
        click_script="${pkgs.writeShellScript "git-click" ''
        REPO_DIR="/Users/monkey/Projects/nix"
        cd "$REPO_DIR" || exit
        sketchybar --set git_repo label="Fetching..."
        git fetch --prune >/dev/null 2>&1

        local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ "$current_branch" != "main" ]; then
          sketchybar --set git_repo label="Not on main"
          exit
        fi

        if ! git rev-parse --verify origin/main >/dev/null 2>&1; then
          sketchybar --set git_repo label="No remote"
          exit
        fi

        local behind_count=$(git rev-list --count origin/main..HEAD 2>/dev/null)
        if [ -z "$behind_count" ]; then
          behind_count=0
        fi

        if [ "$behind_count" -eq 0 ]; then
          sketchybar --set git_repo label="Up to date"
        else
          sketchybar --set git_repo label="$behind_count behind"
        fi
      ''}" \
        on_click=true

      # Add some spacing
      sketchybar --add space space_left left \
        --set space_left width=10 \
        background.drawing=off

      sketchybar --add space space_right right \
        --set space_right width=10 \
        background.drawing=off

      # Initial update
      sketchybar --update
    '';
  };
}
