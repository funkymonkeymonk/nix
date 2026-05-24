# MicroVM configuration tests
# Tests for MicroVM targets including media-center
# Following community best practices from nixpkgs and popular flakes
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Helper to check if a value equals expected
  assertEq = name: expected: actual:
    if actual == expected
    then "${name}: OK"
    else throw "${name}: expected ${toString expected}, got ${toString actual}";

  # Evaluate a microvm configuration without full system build
  # This is faster and follows the pattern from test-services.nix
  evalMicrovmFast = name: let
    eval = lib.evalModules {
      modules = [
        ../modules/common/options.nix
        ../os/microvm.nix
        ../modules/microvm
        ../targets/microvms/${name}.nix
        {
          config._module.args.pkgs = lib.mkDefault pkgs;
          config.nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
          config.myConfig = {
            users = [
              {
                name = "dev";
                email = "dev@localhost";
                fullName = "Development User";
                isAdmin = true;
                sshIncludes = [];
              }
            ];
            onepassword.enable = false;
          };
        }
        {
          options = builtins.listToAttrs (map (option: lib.nameValuePair option (lib.mkOption {
            type = lib.types.anything;
            default = {};
          })) [
            "i18n" "documentation" "environment" "system" "systemd"
            "programs" "networking" "users" "nix" "services"
            "time" "virtualisation" "nixpkgs"
          ]) // {
            myConfig.openclaw = lib.mkOption {
              type = lib.types.anything;
              default = {};
            };
          };
          config = {};
        }
      ];
    };
  in
    eval.config;

  # Get configs for testing
  mediaCenterConfig = evalMicrovmFast "media-center";
  openclawConfig = evalMicrovmFast "openclaw";
  matrixConfig = evalMicrovmFast "matrix";
in {
  # Test media-center MicroVM basic configuration
  mediaCenterConfigTest =
    pkgs.runCommand "test-media-center-config"
    {}
    ''
      echo "=== Testing Media-Center MicroVM Configuration ==="

      # Test hostname
      ${assertEq "hostname" "media-center" mediaCenterConfig.networking.hostName}

      # Test microvm settings
      ${assertEq "microvm IP" "192.168.83.17" mediaCenterConfig.myConfig.microvm.ipAddress}
      ${assertEq "microvm gateway" "192.168.83.1" mediaCenterConfig.myConfig.microvm.gateway}
      ${assertEq "microvm enabled" true mediaCenterConfig.myConfig.microvm.enable}

      echo "All media-center configuration tests passed"
      touch $out
    '';

  # Test Jellyfin service configuration
  mediaCenterJellyfinTest =
    pkgs.runCommand "test-media-center-jellyfin"
    {}
    ''
      echo "=== Testing Media-Center Jellyfin Service ==="

      ${assertEq "jellyfin enabled" true mediaCenterConfig.services.jellyfin.enable}
      ${assertEq "jellyfin openFirewall" true mediaCenterConfig.services.jellyfin.openFirewall}
      ${assertEq "jellyfin user" "jellyfin" mediaCenterConfig.services.jellyfin.user}
      ${assertEq "jellyfin group" "jellyfin" mediaCenterConfig.services.jellyfin.group}

      echo "All Jellyfin service tests passed"
      touch $out
    '';

  # Test *arr services configuration
  mediaCenterArrServicesTest =
    pkgs.runCommand "test-media-center-arr-services"
    {}
    ''
      echo "=== Testing Media-Center *arr Services ==="

      # Sonarr
      ${assertEq "sonarr enabled" true mediaCenterConfig.services.sonarr.enable}
      ${assertEq "sonarr openFirewall" true mediaCenterConfig.services.sonarr.openFirewall}

      # Radarr
      ${assertEq "radarr enabled" true mediaCenterConfig.services.radarr.enable}
      ${assertEq "radarr openFirewall" true mediaCenterConfig.services.radarr.openFirewall}

      # Lidarr
      ${assertEq "lidarr enabled" true mediaCenterConfig.services.lidarr.enable}
      ${assertEq "lidarr openFirewall" true mediaCenterConfig.services.lidarr.openFirewall}

      # Prowlarr
      ${assertEq "prowlarr enabled" true mediaCenterConfig.services.prowlarr.enable}
      ${assertEq "prowlarr openFirewall" true mediaCenterConfig.services.prowlarr.openFirewall}

      # Bazarr
      ${assertEq "bazarr enabled" true mediaCenterConfig.services.bazarr.enable}
      ${assertEq "bazarr openFirewall" true mediaCenterConfig.services.bazarr.openFirewall}

      echo "All *arr services tests passed"
      touch $out
    '';

  # Test Transmission configuration
  mediaCenterTransmissionTest =
    pkgs.runCommand "test-media-center-transmission"
    {}
    ''
      echo "=== Testing Media-Center Transmission ==="

      ${assertEq "transmission enabled" true mediaCenterConfig.services.transmission.enable}
      ${assertEq "transmission openFirewall" true mediaCenterConfig.services.transmission.openFirewall}

      echo "Transmission configuration tests passed"
      touch $out
    '';

  # Test nginx reverse proxy
  mediaCenterNginxTest =
    pkgs.runCommand "test-media-center-nginx"
    {}
    ''
      echo "=== Testing Media-Center Nginx ==="

      ${assertEq "nginx enabled" true mediaCenterConfig.services.nginx.enable}
      ${assertEq "nginx gzip" true mediaCenterConfig.services.nginx.recommendedGzipSettings}
      ${assertEq "nginx optimization" true mediaCenterConfig.services.nginx.recommendedOptimisation}

      echo "Nginx configuration tests passed"
      touch $out
    '';

  # Test firewall ports
  mediaCenterFirewallTest =
    pkgs.runCommand "test-media-center-firewall"
    {}
    ''
      echo "=== Testing Media-Center Firewall Ports ==="

      required_tcp_ports=(80 443 8096 8920 8989 7878 8686 9696 6767 9091 51413)
      required_udp_ports=(51413)

      tcp_ports="${toString mediaCenterConfig.networking.firewall.allowedTCPPorts}"
      udp_ports="${toString mediaCenterConfig.networking.firewall.allowedUDPPorts}"

      for port in "''${required_tcp_ports[@]}"; do
        if echo "$tcp_ports" | grep -qw "$port"; then
          echo "  Port $port (TCP): OK"
        else
          echo "  Port $port (TCP): MISSING"
          exit 1
        fi
      done

      for port in "''${required_udp_ports[@]}"; do
        if echo "$udp_ports" | grep -qw "$port"; then
          echo "  Port $port (UDP): OK"
        else
          echo "  Port $port (UDP): MISSING"
          exit 1
        fi
      done

      echo "All firewall port tests passed"
      touch $out
    '';

  # Test that all MicroVMs have unique IP addresses
  microvmIpUniquenessTest =
    pkgs.runCommand "test-microvm-ip-uniqueness"
    {}
    ''
      echo "=== Testing MicroVM IP Address Uniqueness ==="

      openclaw_ip="${toString openclawConfig.myConfig.microvm.ipAddress}"
      matrix_ip="${toString matrixConfig.myConfig.microvm.ipAddress}"
      media_center_ip="${toString mediaCenterConfig.myConfig.microvm.ipAddress}"

      echo "  openclaw: $openclaw_ip"
      echo "  matrix: $matrix_ip"
      echo "  media-center: $media_center_ip"

      # Check for duplicates
      if [ "$openclaw_ip" = "$matrix_ip" ] || [ "$matrix_ip" = "$media_center_ip" ] || [ "$openclaw_ip" = "$media_center_ip" ]; then
        echo "  ERROR: Duplicate IPs detected!"
        exit 1
      fi

      echo "  All IPs are unique: OK"

      # Verify expected IPs
      [ "$openclaw_ip" = "192.168.83.16" ] || { echo "ERROR: openclaw should be 192.168.83.16"; exit 1; }
      [ "$matrix_ip" = "192.168.83.15" ] || { echo "ERROR: matrix should be 192.168.83.15"; exit 1; }
      [ "$media_center_ip" = "192.168.83.17" ] || { echo "ERROR: media-center should be 192.168.83.17"; exit 1; }

      echo "All MicroVM IP uniqueness tests passed"
      touch $out
    '';

  # Test SSH access is configured
  mediaCenterSshTest =
    pkgs.runCommand "test-media-center-ssh"
    {}
    ''
      echo "=== Testing Media-Center SSH Configuration ==="

      ${assertEq "SSH enabled" true mediaCenterConfig.services.openssh.enable}
      ${assertEq "root login prohibited-password" "prohibit-password" mediaCenterConfig.services.openssh.settings.PermitRootLogin}
      ${assertEq "password auth disabled" false mediaCenterConfig.services.openssh.settings.PasswordAuthentication}

      echo "SSH configuration tests passed"
      touch $out
    '';

  # Test that dev-vm has stateVersion set
  devVmStateVersionTest =
    pkgs.runCommand "test-dev-vm-has-stateversion"
    {src = ../.;}
    ''
      echo "=== Testing dev-vm has system.stateVersion ==="

      if ! grep -q 'stateVersion.*25\.05' $src/targets/microvms/dev-vm.nix; then
        echo "FAIL: dev-vm.nix is missing system.stateVersion = \"25.05\""
        exit 1
      fi

      echo "PASS: dev-vm.nix has stateVersion = \"25.05\""
      touch $out
    '';
}
