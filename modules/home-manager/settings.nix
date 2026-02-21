# Home-manager global settings
# These settings apply to all home-manager configurations
{
  config,
  lib,
  ...
}: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
