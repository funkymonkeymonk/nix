{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    unstable.linkwarden
  ];
}
