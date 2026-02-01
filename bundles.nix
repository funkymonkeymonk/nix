# Consolidated bundle configurations
# This replaces the entire bundles/ directory structure with a single, unified configuration
{
  pkgs,
  lib,
}:
with lib; {
  roles = {
    base = {
      packages = with pkgs; [
        vim
        git
        gh
        devenv
        direnv
        go-task
        rclone
        bat
        jq
        tree
        watchman
        jnv
        zinit
        fzf
        zsh
        # Also includes aliases and common utilities from modules/common/packages.nix
        ripgrep
        fd
        coreutils
        htop
        glow
        antigen
      ];

      config = {
        programs.zsh.enable = true;

        # Shell aliases from bundles/base/aliases.nix
        environment.shellAliases = {
          # Git aliases
          g = "git";
          gst = "git status";
          gpush = "git push";
          gpull = "git pull";
          gd = "git diff";
          gdc = "git diff --cached";
          gco = "git checkout";
          gcob = "git checkout -b";
          gau = "git add -u";
          gauc = "git add -u && git commit -m ";
          gaum = "git add -u && git commit --amend";
          gs = "git stash";
          gsp = "git stash pop";
          gshow = "git stash show -p";
          grm = "git fetch origin && git rebase main";
          grc = "git rebase --continue";
          gm = "git merge";
          gmm = "git fetch origin && git merge origin/main";
          gf = "git fetch --prune";
          gr = "git restore --source";
          grh = "git reset --hard";
          ghv = "gh repo view --web";
          gclean = "git clean -fd";
          gkkb = "git checkout -b $(date +\"%Y%m%d%H%M%S\")";

          # Nix tools
          try = "nix-shell -p";

          # Task runner
          t = "task";
          tb = "task build";
          tt = "task test";

          # Navigation
          "..." = "cd ../..";
        };
      };
    };

    developer = {
      packages = with pkgs; [
        emacs
        clang
        python3
        nodejs
        yarn
        docker
        # colima (moved to darwin platform)
        k3d
        kubectl
        kubernetes-helm
        k9s
        unstable.opencode
      ];

      config = {};
    };

    creative = {
      packages = with pkgs; [
        ffmpeg
        imagemagick
        pandoc
      ];

      config = {
        # Homebrew casks for creative apps (macOS only)
        homebrew = {
          casks = [
            "elgato-stream-deck"
          ];
        };
      };
    };

    gaming = {
      packages = with pkgs; [
        moonlight-qt
      ];

      config = {};
    };

    desktop = {
      packages = with pkgs;
        [
          logseq
        ]
        ++ optional stdenv.isLinux vivaldi;

      config = {};
    };

    workstation = {
      packages = with pkgs; [
        slack
        trippy
        unar
      ];

      config = {};
    };

    entertainment = {
      packages = [];

      config = {
        # Homebrew casks for entertainment apps (macOS only)
        homebrew = {
          casks = [
            "steam"
            "obs"
            "discord"
          ];
        };
      };
    };

    agent-skills = {
      packages = with pkgs; [
        git
        jq
      ];

      config = {
        # Environment variables for skills paths
        environment.sessionVariables = {
          AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
          SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
        };

        # Shell aliases for skills management
        environment.shellAliases = {
          skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
          skills-update = "task agent-skills:update";
          skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
        };
      };
    };

    llms = {
      # Global LLM configuration
      config = {
        # Shared environment variables and configuration
        environment.sessionVariables = {
          LLM_SERVER_HOST = "MegamanX.local";
          LLM_SERVER_PORT = "4000";
        };
      };

      client = {
        # Shared client configuration
        config = {
          # Common client aliases and environment setup
          environment.shellAliases = {
            llm-status = "curl http://MegamanX.local:4000/status";
          };
        };

        opensource = {
          packages = with pkgs; [
            (
              if pkgs ? unstable
              then pkgs.unstable.opencode
              else opencode
            )
          ];

          # Auto-enable agent-skills
          enableAgentSkills = true;

          config = {
            # opencode configuration for connecting to MegamanX litellm server
            environment.sessionVariables = {
              OPENCODE_ENDPOINT = "http://MegamanX.local:4000";
            };
          };
        };

        claude = {
          packages = with pkgs; [
            claude-code
          ];

          # Auto-enable agent-skills
          enableAgentSkills = true;

          config = {
            # Claude-specific configuration
            environment.sessionVariables = {
              CLAUDE_API_BASE = "http://MegamanX.local:4000";
            };
          };
        };
      };

      host = {
        packages = with pkgs; [
          (
            if pkgs ? unstable
            then pkgs.unstable.ollama
            else ollama
          )
        ];

        config = {
          # Configuration for running local models
          # Service configuration handled at home-manager level
        };
      };

      server = {
        packages = with pkgs; [
          # Add litellm and related server packages here when available in nixpkgs
        ];

        config = {
          # litellm server configuration
          # This would include service definitions and startup scripts
        };
      };
    };
  };

  platforms = {
    darwin = {
      packages = with pkgs; [
        google-chrome
        hidden-bar
        goose-cli
        claude-code
        alacritty-theme
        colima
        home-manager
      ];

      config = {
        # 1Password GUI installed via Homebrew on macOS
        # CLI is managed via Nix packages for consistent versions

        # Common Homebrew configuration
        homebrew = {
          enable = true;
          onActivation = {
            autoUpdate = false;
            cleanup = "uninstall";
          };

          casks = [
            # Common macOS applications
            "raycast" # The version in nixpkgs is out of date
            "zed"
            "zen"

            # Terminal emulators
            "ghostty"

            # Entertainment and communication
            "deezer"
            "block-goose"

            # Productivity and utilities
            "sensei"

            # Browser - Vivaldi via Homebrew (not available in nixpkgs for macOS)
            "vivaldi"

            # 1Password GUI (CLI managed via Nix)
            "1password"
          ];
        };
      };
    };

    linux = {
      packages = with pkgs; [
        # Add Linux-specific packages here as needed
      ];

      config = {
        # Linux-specific services or configurations can be added here
      };
    };
  };
}
