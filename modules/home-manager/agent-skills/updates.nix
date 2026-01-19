{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.agent-skills;

  # Upstream repository information
  upstreamRepo = "https://github.com/obra/superpowers.git";
  upstreamBranch = "main";

  # Create the update script
  updateScript = pkgs.writeShellScriptBin "update-agent-skills" ''
    set -euo pipefail

    echo "Updating agent skills from upstream..."

    # Resolve paths at runtime - use defaults if not set
    SKILLS_PATH="$HOME/.config/opencode/skills"
    SUPERPOWERS_PATH="$HOME/.config/opencode/superpowers/skills"

    # Read current version
    VERSION_FILE="$SKILLS_PATH/.upstream-version"
    if [[ -f "$VERSION_FILE" ]]; then
      current_version=$(cat "$VERSION_FILE")
    else
      current_version="none"
    fi

    echo "Current version: $current_version"

    # Clone upstream to temporary directory
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    echo "Cloning upstream repository..."
    git clone --depth 1 --branch "${upstreamBranch}" "${upstreamRepo}" "$temp_dir"

    # Get latest commit hash
    latest_version=$(cd "$temp_dir" && git rev-parse HEAD)

    echo "Latest version: $latest_version"

    if [[ "$current_version" = "$latest_version" ]]; then
      echo "Already up to date"
      exit 0
    fi

    # Update skills
    echo "Updating skills from $temp_dir/skills to $SKILLS_PATH"

    # Ensure directories exist
    mkdir -p "$(dirname "$VERSION_FILE")"
    mkdir -p "$SKILLS_PATH"
    mkdir -p "$SUPERPOWERS_PATH"

    # Copy new skills, preserving custom ones
    if [[ -d "$temp_dir/skills" ]]; then
      rsync -av --delete "$temp_dir/skills/" "$SKILLS_PATH/"
      rsync -av --delete "$temp_dir/skills/" "$SUPERPOWERS_PATH/"
    fi

    # Update version tracking
    echo "$latest_version" > "$VERSION_FILE"

    echo "Skills updated successfully!"
    echo "Version: $latest_version"
    echo "Main skills directory: $SKILLS_PATH"
    echo "Superpowers skills directory: $SUPERPOWERS_PATH"
  '';
in {
  config = lib.mkIf cfg.enable {
    # For now, disable the update script installation to fix the build
    # TODO: Fix package installation for both home-manager and system contexts
    # The script is still available as a package if needed
  };
}
