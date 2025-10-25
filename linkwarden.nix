{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    unstable.linkwarden
  ];
}
# pkg source https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/li/linkwarden/package.nix

