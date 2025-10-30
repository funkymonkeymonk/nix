{
  config,
  lib,
  pkgs,
  ...
}: {
  # Consolidated `home` attribute set
  home = {
    stateVersion = "25.05";

    packages = with pkgs; [
      docker
    ];

    shellAliases = {
      g = "git";
      t = "task";
      tb = "task build";
      tt = "task test";
      "..." = "cd ../..";
      dip = "docker inspect --format '{{ .NetworkSettings.IPAddress }}'";
      dkd = "docker run -d -P";
      dki = "docker run -t -i -P";
      gauc = "git add -u && git commit -m ";
      gst = "git status";
      gaum = "git add -u && git commit --amend";
      gpush = "git push";
      gpull = "git pull";
      gd = "git diff";
      gdc = "git diff --cached";
      gco = "git checkout";
      ghv = "gh repo view --web";
      gs = "git stash";
      gsp = "git stash pop";
      gshow = "git stash show -p";
      grm = "git fetch origin && git rebase main";
      grc = "git rebase --continue";
      gm = "git merge";
      gmm = "git fetch origin && git git merge origin/main";
      gf = "git fetch --prune";
      gr = "git restore --source";
      grh = "git reset --hard";
      try = "nix-shell -p";
    };
  };

  # Consolidated `programs` attribute set
  programs = {
    alacritty = {
      enable = true;
      settings = {
        font.size = 14;
        window.decorations = "Buttonless";
        window.padding = {
          x = 10;
          y = 6;
        };
        mouse.hide_when_typing = true;
      };
    };

    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
    };

    ssh = {
      enable = true;

      extraConfig = lib.optionalString pkgs.stdenv.isDarwin ''
        Host *
          IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      '';

      includes = lib.optionals (config.home.username == "monkey") [
        "/Users/monkey/.colima/ssh_config"
      ];
    };
  };

  # Ensure a managed per-user SSH config is created on macOS so the 1Password
  # IdentityAgent socket is available to the SSH client. This writes ~/.ssh/config.
  home.file."/.ssh/config".text = lib.optionalString pkgs.stdenv.isDarwin ''
    Host *
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  '';
}
