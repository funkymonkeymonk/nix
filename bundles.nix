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
      packages = with pkgs;
        [
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
        ]
        ++ lib.optionals stdenv.isLinux [
          krunvm
        ]
        ++ [
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

    oci-builder = {
      packages = with pkgs; [
        # OCI image building
        apko # Build OCI images using APK directly without Dockerfile
        img # Standalone, daemon-less, unprivileged Dockerfile and OCI compatible container image builder
        buildkit # Concurrent, cache-efficient, and Dockerfile-agnostic builder toolkit

        # Container registry tools
        skopeo # Work with remote image registries
        regctl # Docker and OCI Registry Client
        regclient # Registry client tools

        # Container tooling
        docker # Docker CLI for compatibility
        docker-compose # Docker Compose for multi-container applications
        nerdctl # Docker-compatible CLI for containerd
        # Note: colima should be installed manually due to security issues: brew install colima

        # Image analysis and security
        dive # Tool for exploring each layer in a docker image
        diffoci # Diff for Docker and OCI container images
        trivy # Simple and comprehensive vulnerability scanner for containers

        # Image optimization
        docker-slim # Minify and secure Docker containers

        # Additional utilities
        jq # JSON processing for inspecting manifests
        yq # YAML processing for configuration files
      ];

      config = {
        # Shell aliases for common OCI operations
        environment.shellAliases = {
          # Image building aliases
          "oci-build" = "apko build";
          "img-build" = "img build";
          "docker-build" = "docker build .";

          # Registry operations
          "oci-copy" = "skopeo copy";
          "oci-inspect" = "skopeo inspect";
          "reg-list" = "regctl repo ls";
          "reg-manifest" = "regctl manifest get";

          # Image analysis
          "img-dive" = "dive";
          "img-diff" = "diffoci";
          "img-scan" = "trivy image";

          # Container runtime management (colima aliases for manual installation)
          # Note: colima should be installed manually: brew install colima
          "colima-start" = "colima start --cpu 4 --memory 4 --disk 60";
          "colima-stop" = "colima stop";
          "colima-status" = "colima status";
          "colima-reset" = "colima reset";

          # Utilities
          "docker-clean" = "docker system prune -af";
          "docker-stats" = "docker stats --no-stream";
        };

        # Environment variables for container development
        environment.sessionVariables = {
          DOCKER_BUILDKIT = "1";
          COMPOSE_DOCKER_CLI_BUILD = "1";
          # Default registry settings
          REGISTRY = "docker.io";
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

          taps = [
            "slp/krun"
          ];

          brews = [
            "krunvm"
          ];

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
