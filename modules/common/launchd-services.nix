# Centralized launchd service bootstrap and verification
# Works around macOS Tahoe (26)+ where launchctl load -w is broken and services
# exit with EX_CONFIG (78). Instead uses:
#   1. launchctl bootout  — remove stale registration
#   2. launchctl bootstrap — register properly  (modern API)
#   3. launchctl kickstart — force start
#   4. launchctl print    — verify running state
#
# Service modules register themselves in myConfig.serviceRegistry
# and this module handles all activation-time bootstrap centrally.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.serviceRegistry;
  services = builtins.attrValues cfg;
in {
  config = mkIf (services != []) {
    system.activationScripts.postActivation.text = mkAfter ''
      echo "Bootstrapping launchd services..." >&2
      ${concatStringsSep "\n" (map (svc: ''
          echo "  ${svc.name} (${svc.launchdLabel}): bootstrapping..." >&2

          # macOS Tahoe compat: proper bootstrap sequence
          # Kill first so bootout doesn't hang waiting for SIGTERM
          launchctl kill SIGKILL "system/${svc.launchdLabel}" 2>/dev/null || true

          # bootout removes stale registrations that cause EX_CONFIG on load
          launchctl bootout "system/${svc.launchdLabel}" 2>/dev/null || true

          # bootstrap registers the service properly (vs broken load -w)
          if ! launchctl bootstrap system "/Library/LaunchDaemons/${svc.launchdLabel}.plist" 2>/dev/null; then
            # If bootstrap fails, the service might still be bootstrapped from a previous run
            # Try to work with what we have
            :
          fi

          # kickstart forces the service to start immediately (no -k: nothing to kill)
          launchctl kickstart "system/${svc.launchdLabel}" 2>/dev/null || true

          # Short sleep: kickstart is async, service needs a moment to become "running"
          sleep 1

          # Verify using launchctl print (works on all modern macOS)
          state_info=$(launchctl print "system/${svc.launchdLabel}" 2>/dev/null) || state_info=""
          if echo "$state_info" | grep -q "state = running"; then
            echo "    ${svc.name}: running" >&2
          else
            last_exit=$(echo "$state_info" | grep "last exit code" | head -1)
            active=$(echo "$state_info" | grep "active count" | head -1)
            if echo "$state_info" | grep -q "active count = [1-9]"; then
              echo "    ${svc.name}: running (active count > 0)" >&2
            elif [ -z "$last_exit" ] && [ -z "$active" ]; then
              echo "    ${svc.name}: NOT FOUND in launchd" >&2
            elif echo "$last_exit" | grep -q "never exited"; then
              echo "    ${svc.name}: running (never exited)" >&2
            else
              echo "    ${svc.name}: NOT RUNNING (''${last_exit})" >&2
            fi
          fi
        '')
        services)}
      echo "Launchd services bootstrap complete" >&2
    '';
  };
}
