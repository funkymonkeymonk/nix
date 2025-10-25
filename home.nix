{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.ssh = {
    enable = true;

    extraConfig = lib.optionalString pkgs.stdenv.isDarwin ''
      Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';

    includes = lib.optionals (config.home.username == "monkey") [
      "/Users/monkey/.colima/ssh_config"
    ];
  };

  # Ensure a managed per-user SSH config is created on macOS so the 1Password
  # IdentityAgent socket is available to the SSH client. This writes ~/.ssh/config.
  home.file."/.ssh/config".text = lib.optionalString pkgs.stdenv.isDarwin ''
    Host *
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  '';
}
