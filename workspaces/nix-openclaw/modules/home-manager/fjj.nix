{
  pkgs,
  lib,
  ...
}: let
  # Platform-specific mirror location (macOS uses ~/src since /srv is read-only)
  mirrorRoot = "$HOME/src";

  # Inject configuration into the script by replacing the default values
  fjjScript = pkgs.writeShellScriptBin "fjj" (
    lib.replaceStrings
    [''MIRROR_ROOT="/srv/github"'']
    [''MIRROR_ROOT="${mirrorRoot}"'']
    (builtins.readFile ./scripts/fjj)
  );

  # Get the path to the binary for use in zsh wrapper
  fjjBinaryPath = "${fjjScript}/bin/fjj";
in {
  home = {
    packages = [fjjScript];

    file."workspaces/.keep".text = "";

    activation.createSrvDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mirror_root="${mirrorRoot}"
      if [ ! -d "$mirror_root" ]; then
        $DRY_RUN_CMD mkdir -p $VERBOSE_ARG "$mirror_root" 2>/dev/null || echo "Note: Could not create $mirror_root"
      fi
    '';
  };

  # Zsh integration for cd behavior and completions
  programs.zsh.initContent = lib.mkAfter ''
    # FJJ workflow aliases
    alias fjj-add='fjj --add'
    alias fjj-list='fjj --list'
    alias fjj-clean='fjj --clean'
    alias fjj-status='fjj --status'

    # Smart cd wrapper for fjj
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
        fi
      fi

      # Cleanup
      rm -f "$workspace_path_file"

      return $exit_code
    }

    # FZF-powered repo picker for fjj --add
    # Trigger with: Alt-a
    _fjj_add_fzf() {
      local repos cache_file="$HOME/.cache/fjj-repos"

      # Cache repos for 5 minutes
      if [ ! -f "$cache_file" ] || [ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -gt 300 ]; then
        mkdir -p "$(dirname "$cache_file")"
        {
          echo "=== YOUR REPOS ==="
          gh repo list --limit 100 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null
          echo ""
          echo "=== ORGS ==="
          gh org list --json login --jq '.[].login' 2>/dev/null | while read org; do
            gh repo list "$org" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null
          done
          echo ""
          echo "=== STARRED ==="
          gh api user/starred --jq '.[].full_name' 2>/dev/null
        } | grep -v '^===' | grep -v '^$' | sort -u > "$cache_file"
      fi

      repos=$(cat "$cache_file" 2>/dev/null)

      if [ -z "$repos" ]; then
        echo "No repos found. Make sure 'gh auth status' works." >&2
        return 1
      fi

      # Use fzf to select
      local selected=$(echo "$repos" | fzf --height 40% --reverse \
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

    # Bind Alt-a to trigger fjj --add with fzf
    zle -N _fjj_add_fzf
    bindkey '^[a' _fjj_add_fzf  # Alt-a
  '';
}
