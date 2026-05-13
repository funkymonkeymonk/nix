{
  config,
  options,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
  inherit (config.myConfig) isDarwin;
  # Check if the opnix module is available (onepassword-secrets option exists)
  hasOpnix = builtins.hasAttr "onepassword-secrets" (options.services or {});
in {
  config = mkIf cfg.enable (mkMerge [
    # On NixOS, use programs._1password which sets up PAM integration and the CLI.
    # On Darwin, the CLI is provided via environment.systemPackages since
    # programs._1password is a NixOS-only option.
    # Use mkIf (not optionalAttrs) so isDarwin is evaluated lazily, avoiding
    # infinite recursion during module argument binding.
    (mkIf (!isDarwin) {
      programs._1password = {
        enable = true;
        package = pkgs._1password-cli;
      };
    })
    (mkIf isDarwin {
      environment.systemPackages = [pkgs._1password-cli];
    })
    (optionalAttrs (hasOpnix && cfg.secrets != {}) {
      # Enable opnix secrets service when the module is available (NixOS only).
      # This makes the infrastructure available but requires a token file to function.
      # To get a token: https://developer.1password.com/docs/service-accounts/get-started/
      services.onepassword-secrets = {
        enable = true;
        inherit (cfg) tokenFile secrets;
      };
    })
  ]);
}
