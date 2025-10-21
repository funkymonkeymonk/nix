{ config, lib, pkgs, ... }:
{
  # Workstation role bundle - general productivity tools
  environment.systemPackages = with pkgs; [
    # Productivity tools
    slack
    trippy

    # System utilities
    coreutils
    the-unarchiver

    # Development support
    watchman
    jnv
  ];
}