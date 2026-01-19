{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.agent-skills;
  
  # Upstream repository information
  upstreamRepo = "https://github.com/obra/superpowers.git";
  upstreamBranch = "main";
  
  # Version tracking file path
  versionFile = "${config.home.homeDirectory}/.config/opencode/superpowers/.upstream-version";
  
in
{
  config = lib.mkIf cfg.enable {
    # Create update script
    home.packages = [
      (pkgs.writeShellScriptBin "update-agent-skills" ''
        set -euo pipefail
        
        echo "Updating agent skills from upstream..."
        
        # Read current version
        if [[ -f "${versionFile}" ]]; then
          current_version=$(cat "${versionFile}")
        else
          current_version="none"
        fi
        
        echo "Current version: $current_version"
        
        # Clone upstream to temporary directory
        temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT
        
        git clone --depth 1 "${upstreamRepo}" "$temp_dir"
        
        # Get latest commit hash
        latest_version=$(cd "$temp_dir" && git rev-parse HEAD)
        
        echo "Latest version: $latest_version"
        
        if [[ "$current_version" = "$latest_version" ]]; then
          echo "Already up to date"
          exit 0
        fi
        
        # Update skills
        echo "Updating skills from $temp_dir/skills to ${config.home.homeDirectory}/.config/opencode/skills"
        mkdir -p "${config.home.homeDirectory}/.config/opencode/skills"
        mkdir -p "${config.home.homeDirectory}/.config/opencode/superpowers/skills"
        
        # Copy new skills, preserving custom ones
        if [[ -d "$temp_dir/skills" ]]; then
          rsync -av --delete "$temp_dir/skills/" "${config.home.homeDirectory}/.config/opencode/skills/"
          rsync -av --delete "$temp_dir/skills/" "${config.home.homeDirectory}/.config/opencode/superpowers/skills/"
        fi
        
        # Update version tracking
        mkdir -p "$(dirname "${versionFile}")"
        echo "$latest_version" > "${versionFile}"
        
        echo "Skills updated successfully!"
        echo "Version: $latest_version"
      '')
    ];
  };
}
