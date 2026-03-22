# Consolidated bundle configurations
{pkgs}:
with pkgs.lib; {
  roles = {
    # Foundation - Development environment built on top of core
    # Provides productive development tools on all systems
    # Note: Core (git, vim, curl, wget, coreutils) is always included separately
    # Required configuration: none (works out of the box)
    # Optional configuration: SSH authorized keys for remote access
    foundation = {
      packages = with pkgs; [
        # Note: Core provides git, vim, curl, wget, coreutils

        # Editors and terminals
        helix
        htop
        zellij

        # Data processing
        jq

        # Security
        _1password-cli

        # Git and version control
        gh
        jujutsu
        delta

        # Navigation and search
        tree
        zoxide
        fzf
        ripgrep
        fd

        # Development tools
        devenv
        direnv
        rclone
        bat
        watchman
        jnv
        docker
        # Colima provides Docker runtime on macOS (Linux uses native Docker)
        colima

        # Shell ecosystem
        zinit
        zsh
        glow
        antigen
      ];

      config = {
        # Enable 1Password on all platforms
        # On NixOS: uses programs._1password
        # On Darwin: comes with 1password cask (see platforms.darwin)
        myConfig.onepassword.enable = true;

        # Enable syncthing for file sync on all systems
        myConfig.syncthing.enable = true;

        programs.zsh.enable = true;

        environment.variables = {
          EDITOR = "helix";
          VISUAL = "helix";
        };

        environment.shellAliases = {
          # Quick system info
          sysinfo = "uname -a";

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
          gkkb = ''git checkout -b $(date +"%Y%m%d%H%M%S")'';

          # Nix tools
          try = "nix-shell -p";

          # Navigation
          "..." = "cd ../..";
        };
      };
    };

    developer = {
      packages = with pkgs; [
        clang
        python3
        nodejs
        yarn
        k3d
        kubectl
        kubernetes-helm
        k9s
        gh-dash
        gomuks
        slidev-cli
        yaks
      ];

      config = {
        myConfig.development.enable = true;
        myConfig.fjj.enable = true;
        myConfig.zellij.enable = true;

        environment.shellAliases = {
          # Yaks shortcuts
          yl = "yx ls";
          yla = "yx ls --all";
          ya = "yx add";
          yd = "yx done";
          ys = "yx sync";
        };
      };
    };

    creative = {
      packages = with pkgs; [
        ffmpeg
        imagemagick
        pandoc
      ];

      config = {
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
          super-productivity
          # element-desktop on Darwin requires Xcode 26+ to build, use Homebrew cask instead
        ]
        ++ optional stdenv.hostPlatform.isLinux element-desktop
        ++ optional stdenv.hostPlatform.isLinux vivaldi;

      config = {
        homebrew = {
          casks = [
            "element"
          ];
        };
      };
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
      # Note: git and jq are already in foundation
      packages = [];

      config = {
        # Use sessionVariables on NixOS, variables on Darwin
        environment = {
          sessionVariables = {
            AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
            SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
          };
          variables = {
            AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
            SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
          };
        };

        environment.shellAliases = {
          skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
          skills-update = "devenv tasks run agent-skills:update";
          skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
        };
      };
    };

    # Flattened LLM roles (previously nested under roles.llms.*)
    llm-client = {
      packages = with pkgs; [
        opencode
        rtk
      ];

      enableAgentSkills = true;

      config = {};
    };

    llm-claude = {
      packages = with pkgs; [
        claude-code
      ];

      enableAgentSkills = true;

      config = {};
    };

    llm-host = {
      packages = with pkgs; [ollama];

      config = {
        myConfig.ollama = {
          enable = true;
          host = "0.0.0.0";
          port = 11434;
          models = ["qwen3.5:2b" "qwen3.5" "qwen3.5:122b"];
        };
      };
    };

    llm-server = {
      packages = [];

      config = {};
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
        home-manager
      ];

      config = {
        homebrew = {
          enable = true;
          onActivation = {
            autoUpdate = false;
            cleanup = "uninstall";
          };

          casks = [
            "raycast"
            "zed"
            "zen"
            "ghostty"
            "deezer"
            "block-goose"
            "sensei"
            "vivaldi"
            "1password"
          ];
        };
      };
    };

    linux = {
      packages = [];
      config = {};
    };
  };
}
