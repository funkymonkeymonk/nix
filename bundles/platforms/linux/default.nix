{ config, lib, pkgs, ... }:
{
  # Linux-specific packages and configuration
  environment.systemPackages = with pkgs; [
    # Linux-specific utilities
    # Add Linux-specific packages here as needed
  ];

  # Linux-specific services or configurations can be added here
}