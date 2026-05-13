# OpenClaw hardening overlay
# Adds security hardening options to the official nix-openclaw module
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.openclaw;

  # Only apply hardening on NixOS (not Darwin)
  isNixOS = builtins.hasAttr "systemd" config;
in {
  options.myConfig.openclaw.hardening = {
    enable =
      lib.mkEnableOption "OpenClaw systemd service hardening"
      // {
        default = isNixOS;
      };

    noNewPrivileges = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prevent the service from gaining new privileges";
    };

    protectSystem = lib.mkOption {
      type = lib.types.enum ["true" "full" "strict"];
      default = "strict";
      description = "Make /usr and /boot read-only (full) or entire filesystem (strict)";
    };

    protectHome = lib.mkOption {
      type = lib.types.enum ["true" "read-only" "tmpfs"];
      default = "read-only";
      description = "Protect home directories";
    };

    privateTmp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use private /tmp and /var/tmp";
    };

    protectKernelTunables = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Make kernel tunables read-only";
    };

    protectKernelModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Block kernel module loading/unloading";
    };

    protectControlGroups = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Make cgroup tree read-only";
    };

    restrictSUIDSGID = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Block creating SUID/SGID files";
    };

    privateDevices = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Private /dev. Disable if voice features needed.";
    };

    restrictNamespaces = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Block namespace creation. Disable if sandboxing needed.";
    };

    restrictAddressFamilies = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = ["AF_INET" "AF_INET6" "AF_NETLINK"];
      description = "Restrict socket address families";
    };

    systemCallFilter = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "System call filter (seccomp). e.g. ['@system-service' '~@privileged']";
    };

    memoryDenyWriteExecute = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Block creating writable+executable memory mappings. May break Node.js JIT.";
    };

    lockPersonality = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Lock execution domain personality";
    };

    resourceLimits = {
      memoryMax = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "3G";
        description = "Maximum memory limit (e.g., '3G', '512M')";
      };

      cpuQuota = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "80%";
        description = "CPU quota percentage";
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.hardening.enable && isNixOS) {
    systemd.services.openclaw-gateway.serviceConfig =
      {
        # Security hardening
        NoNewPrivileges = cfg.hardening.noNewPrivileges;
        ProtectSystem = cfg.hardening.protectSystem;
        ProtectHome = cfg.hardening.protectHome;
        PrivateTmp = cfg.hardening.privateTmp;
        ProtectKernelTunables = cfg.hardening.protectKernelTunables;
        ProtectKernelModules = cfg.hardening.protectKernelModules;
        ProtectControlGroups = cfg.hardening.protectControlGroups;
        RestrictSUIDSGID = cfg.hardening.restrictSUIDSGID;
        PrivateDevices = cfg.hardening.privateDevices;
        RestrictNamespaces = cfg.hardening.restrictNamespaces;
        LockPersonality = cfg.hardening.lockPersonality;

        # Resource limits
        MemoryMax = lib.mkIf (cfg.hardening.resourceLimits.memoryMax != null) cfg.hardening.resourceLimits.memoryMax;
        CPUQuota = lib.mkIf (cfg.hardening.resourceLimits.cpuQuota != null) cfg.hardening.resourceLimits.cpuQuota;

        # Read/write paths
        ReadWritePaths = ["/var/lib/openclaw" "/run/openclaw"];
      }
      // lib.optionalAttrs (cfg.hardening.restrictAddressFamilies != null) {
        RestrictAddressFamilies = cfg.hardening.restrictAddressFamilies;
      }
      // lib.optionalAttrs (cfg.hardening.systemCallFilter != null) {
        SystemCallFilter = cfg.hardening.systemCallFilter;
      }
      // lib.optionalAttrs cfg.hardening.memoryDenyWriteExecute {
        MemoryDenyWriteExecute = true;
      };
  };
}
