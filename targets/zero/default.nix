# Zero - Gaming/desktop NixOS machine (NVMe + AMD CPU/GPU)
{
  config,
  pkgs,
  lib,
  mkUser,
  inputs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
      roles = {
        developer.enable = true;
        desktop.enable = true;
        opencode.enable = true;
        pi.enable = true;
      };
      tailscale = {
        enable = true;
        authKeyOpnixItem = "Tailscale Auth Key/credential";
      };
      desktop = {
        enable = true;
        autoLoginUser = "monkey";
      };
      gaming.enable = true;
      streaming.enable = true;
      onepassword = {
        enable = true;
        defaultVault = "Homelab";
      };

      # Cloud-only LLM access via OpenCode Go (falls back to OpenCode Zen).
      # Mirrors the MegamanX setup: no local models on this machine.
      opencode = {
        model = "opencode-go/gpt-5.6-luna";
        # Replace the role's local model default with the cloud provider.
        providers = lib.mkForce {
          "opencode-go" = {
            name = "OpenCode Go";
            onePasswordItem = "op://Homelab/OpenCode Go API/credential";
          };
        };
      };

      # Mirror MegamanX's pi setup, minus the local oMLX/Bifrost model.
      pi = {
        pluginsSource = inputs.pi-plugins.outPath or null;
        npmPackages = {
          "pi-opencode-provider" = "^0.7.3";
          "pi-web-access" = "^0.10.7";
          "pi-subagents" = "^0.33.1";
        };

        settings = {
          theme = "dark";
          defaultProvider = "opencode-go";
          defaultModel = "gpt-5.6-luna";
          editor = {
            vimMode = true;
          };
          compaction = {
            enabled = true;
            reserveTokens = 24576;
            keepRecentTokens = 16000;
          };
          retry = {
            enabled = true;
            maxRetries = 5;
            baseDelayMs = 3000;
            provider = {
              timeoutMs = 600000;
              maxRetries = 0;
              maxRetryDelayMs = 60000;
            };
          };
          httpIdleTimeoutMs = 300000;
        };

        agentsMd = ''
          # Global Agent Instructions

          This is a Nix-managed system. When working with Nix configurations:
          - Always run `devenv tasks run check:lint` before committing
          - Use the existing module patterns in modules/
          - Follow the conventional commit style
        '';

        # OpenCode Go falls back to OpenCode Zen, so a single provider + key
        # covers both. Replace the role's local bifrost model.
        models = lib.mkForce {
          "opencode-go" = {
            name = "OpenCode Go";
            provider = "opencode-go";
            modelId = "";
            onePasswordItem = "op://Homelab/OpenCode Go API/credential";
          };
        };

        prompts.review = ''
          Review this code for:
          1. Bugs and logic errors
          2. Security issues
          3. Performance problems
          4. Nix best practices (if applicable)

          Provide specific suggestions with line numbers.
        '';
      };
    };

  networking = {
    hostName = "zero";
    networkmanager.enable = true;
    firewall.enable = false;
  };

  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    discord

    # Hardware-specific packages for connected peripherals
    liquidctl # Corsair H100i RGB PRO XT AIO cooling control
    openrgb # IT8297 RGB LED controller on motherboard
    openrazer-daemon # Razer Naga Trinity mouse (driver userspace)
    polychromatic # GUI for openrazer device management
    nvme-cli # Samsung NVMe SSD diagnostics
    smartmontools # Drive health monitoring
    v4l-utils # Logitech C920 webcam (v4l2-ctl)
    amdgpu_top # AMD GPU monitoring
    libva-utils # AMD GPU VA-API diagnostics (vainfo)
    vulkan-tools # AMD GPU Vulkan diagnostics (vulkaninfo)
    pciutils # Hardware debug (lspci)
    usbutils # Hardware debug (lsusb)
  ];

  # Razer Naga Trinity mouse support (udev rules + userspace daemon)
  hardware.openrazer = {
    enable = true;
    users = ["monkey"];
  };

  # Hardware: NVMe, AMD CPU/GPU
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Disable sleep/hibernate (always-on machine)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };
}
