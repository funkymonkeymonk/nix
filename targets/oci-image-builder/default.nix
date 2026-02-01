{
  config,
  pkgs,
  lib,
  ...
}: {
  # OCI Image Builder Configuration
  # This target provides tools for building and managing OCI container images

  imports = [
    # No hardware configuration needed for container image building
  ];

  # Core OCI image building tools
  environment.systemPackages = with pkgs; [
    # OCI image building
    apko # Build OCI images using APK directly without Dockerfile
    img # Standalone, daemon-less, unprivileged Dockerfile and OCI compatible container image builder
    buildkit # Concurrent, cache-efficient, and Dockerfile-agnostic builder toolkit

    # Container registry tools
    skopeo # Work with remote image registries
    regctl # Docker and OCI Registry Client
    regclient # Registry client tools

    # Container tooling
    docker # Docker CLI for compatibility
    docker-compose # Docker Compose for multi-container applications
    nerdctl # Docker-compatible CLI for containerd

    # Image analysis and security
    dive # Tool for exploring each layer in a docker image
    diffoci # Diff for Docker and OCI container images
    trivy # Simple and comprehensive vulnerability scanner for containers

    # Image optimization
    docker-slim # Minify and secure Docker containers

    # Additional utilities
    jq # JSON processing for inspecting manifests
    yq # YAML processing for configuration files
  ];

  # System configuration for image building
  # Note: colima will be managed manually due to dependency issues
  # Users can start/stop with: colima-start, colima-stop aliases
  virtualisation.docker.enable = lib.mkDefault true; # Docker compatibility layer

  # User configuration for container tools
  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = [
      "wheel"
      "docker" # Allow user to interact with docker daemon
    ];
    shell = pkgs.zsh;
    home = "/home/monkey";
  };

  # Environment and shell aliases for container development
  environment = {
    sessionVariables = {
      DOCKER_BUILDKIT = "1";
      COMPOSE_DOCKER_CLI_BUILD = "1";
      # Default registry settings
      REGISTRY = "docker.io";
    };

    shellAliases = {
    # Image building aliases
    "oci-build" = "apko build";
    "img-build" = "img build";
    "docker-build" = "docker build .";

    # Registry operations
    "oci-copy" = "skopeo copy";
    "oci-inspect" = "skopeo inspect";
    "reg-list" = "regctl repo ls";
    "reg-manifest" = "regctl manifest get";

    # Image analysis
    "img-dive" = "dive";
    "img-diff" = "diffoci";
    "img-scan" = "trivy image";

    # Utilities
    "docker-clean" = "docker system prune -af";
    "docker-stats" = "docker stats --no-stream";
  };

  # System state version
  system.stateVersion = "25.05";

  # Networking configuration (minimal for image building)
  networking = {
    hostName = "oci-image-builder";
    # Use network manager for flexibility
    networkmanager.enable = true;
  };

  # Time zone
  time.timeZone = "America/New_York";

  # File system configuration (required by NixOS)
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/CHANGE-THIS-UUID";
    fsType = "ext4";
  };

  # Boot configuration (required by NixOS)
  boot.loader.systemd-boot.enable = true;
}
