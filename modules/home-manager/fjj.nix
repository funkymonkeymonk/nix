{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  # Platform-specific mirror location (macOS uses ~/src since /srv is read-only)
  mirrorRoot =
    if osConfig.myConfig.isDarwin
    then "$HOME/src"
    else "/srv/github";

  # Read the script and inject configuration
  fjjScript = pkgs.writeShellScriptBin "fjj" (
    lib.replaceStrings
    ["MIRROR_ROOT=\"\${FJJ_MIRROR_ROOT:-/srv/github}\""]
    ["MIRROR_ROOT=\"\${FJJ_MIRROR_ROOT:-${mirrorRoot}}\""]
    (builtins.readFile ./scripts/fjj)
  );

  # Get the path to the binary for use in zsh wrapper
  fjjBinaryPath = "${fjjScript}/bin/fjj";
in {
  home = {
    packages = [fjjScript];

    # Ensure workspaces directory exists
    file."workspaces/.keep".text = "";

    # Create mirror root on activation
    activation.createMirrorDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mirror_root="${mirrorRoot}"
      if [ ! -d "$mirror_root" ]; then
        $DRY_RUN_CMD mkdir -p $VERBOSE_ARG "$mirror_root" 2>/dev/null || echo "Note: Could not create $mirror_root"
      fi
    '';
  };

  # Zsh integration for cd behavior and helpful aliases
  programs.zsh.initContent = lib.mkAfter ''
    # FJJ - Fast Jujutsu Workflow
    # Mirrors are at: ${mirrorRoot}
    # Workspaces are at: ~/workspaces

    # Export environment variables
    export FJJ_MIRROR_ROOT="${mirrorRoot}"
    export FJJ_WORKSPACE_ROOT="$HOME/workspaces"

    # Smart cd wrapper for fjj that auto-cd's to new workspaces
    fjj() {
      local workspace_path_file
      local workspace_path

      # Create temp file to receive workspace path from fjj
      workspace_path_file=$(mktemp)

      # Run fjj binary, passing temp file path via environment
      # Fjj will write the workspace path to this file if one is created/used
      FJJ_WORKSPACE_PATH_FILE="$workspace_path_file" ${fjjBinaryPath} "$@"
      local exit_code=$?

      # Check if workspace path was written
      if [ -s "$workspace_path_file" ]; then
        workspace_path=$(cat "$workspace_path_file")
        if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
          echo ""
          echo "📂 Entering workspace: $(basename "$workspace_path")"
          cd "$workspace_path"

          # Show helpful next steps
          echo ""
          echo "Next steps:"
          echo "  jj new           # Start a new commit"
          echo "  jj status        # Check current state"
          echo "  jj-pr --help     # Show PR creation help"
        fi
      fi

      # Cleanup
      rm -f "$workspace_path_file"

      return $exit_code
    }

    # FZF-powered repo picker for fjj --add (Alt-a)
    _fjj_add_fzf() {
      local repos cache_file="$HOME/.cache/fjj-repos"
      local cache_timeout=300  # 5 minutes

      # Cache repos for faster subsequent use
      if [ ! -f "$cache_file" ] || [ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -gt $cache_timeout ]; then
        mkdir -p "$(dirname "$cache_file")"
        {
          echo "=== YOUR REPOS ==="
          gh repo list --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true
          echo ""
          echo "=== ORGS ==="
          gh org list --json login --jq '.[].login' 2>/dev/null | while read -r org; do
            gh repo list "$org" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null || true
          done
          echo ""
          echo "=== STARRED ==="
          gh api user/starred --jq '.[].full_name' 2>/dev/null || true
        } | grep -v '^===' | grep -v '^$' | sort -u > "$cache_file"
      fi

      repos=$(cat "$cache_file" 2>/dev/null || echo "")

      if [ -z "$repos" ]; then
        echo "No repos found. Make sure 'gh auth status' works." >&2
        return 1
      fi

      # Use fzf to select
      local selected
      selected=$(echo "$repos" | fzf --height 40% --reverse \
        --prompt="Select repo to mirror: " \
        --preview "gh repo view {} --json description,stargazersCount,updatedAt --template '{{.description}}\n⭐ {{.stargazersCount}} stars | Updated: {{.updatedAt}}' 2>/dev/null || echo 'Preview unavailable'" \
        --preview-window=right:50%)

      if [ -n "$selected" ]; then
        # Insert the selected repo into the command line
        LBUFFER="fjj --add $selected"
        RBUFFER=""
        zle redisplay
        zle accept-line
      fi

      return 0
    }

    # Register the widget and bind Alt-a
    zle -N _fjj_add_fzf
    bindkey '^[a' _fjj_add_fzf  # Alt-a

    # Helpful aliases for jj workflow integration
    alias fjj-add='fjj --add'
    alias fjj-list='fjj --list'
    alias fjj-clean='fjj --clean'
    alias fjj-status='fjj --status'
    alias fjj-session='fjj --session'
  '';
}
