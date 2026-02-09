{pkgs, ...}: {
  packages = [
    pkgs.go-task
    pkgs.alejandra
    # Additional Nix development tools
    pkgs.nixpkgs-fmt
    pkgs.statix
    pkgs.deadnix
    pkgs.nil
    pkgs.nix-tree
    pkgs.nvd
    # Useful CLI tools
    pkgs.ripgrep
    pkgs.fd
    pkgs.jq
    pkgs.envsubst
    # Documentation
    pkgs.mdbook
    # YAML linting
    pkgs.yamllint
    pkgs.yamlfmt
    pkgs.nixd
    pkgs.optnix
    # Cachix CLI for pushing to binary cache
    pkgs.cachix
    # IDE tools (task ide)
    pkgs.zellij
    pkgs.yazi
    pkgs.helix
    pkgs.gh-dash
    # GitHub Actions local runner
    pkgs.act
  ];

  # Disable automatic Cachix management so devenv can run without being a trusted Nix user
  cachix = {
    enable = false;
  };

  # https://devenv.sh/git-hooks/
  git-hooks = {
    hooks = {
      alejandra = {
        enable = true;
      };
      statix = {
        enable = true;
      };
      deadnix = {
        enable = true;
        entry = "${pkgs.deadnix}/bin/deadnix --no-underscore";
      };
      yamllint = {
        enable = true;
      };
    };
  };

  # See full reference at https://devenv.sh/reference/options/
}
