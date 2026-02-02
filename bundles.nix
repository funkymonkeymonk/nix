# Consolidated bundle configurations
{pkgs}:
with pkgs.lib; {
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
        ripgrep
        fd
        coreutils
        htop
        glow
        antigen
      ];

      config = {
        programs.zsh.enable = true;

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
        k3d
        kubectl
        kubernetes-helm
        k9s
        # opencode is provided by llm-client role
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
        environment.sessionVariables = {
          AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
          SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
        };

        environment.shellAliases = {
          skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
          skills-update = "task agent-skills:update";
          skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
        };
      };
    };

    # Flattened LLM roles (previously nested under roles.llms.*)
    llm-client = {
      packages = with pkgs; [
        opencode
      ];

      enableAgentSkills = true;

      config = {
        environment.sessionVariables = {
          LLM_SERVER_HOST = "MegamanX.local";
          LLM_SERVER_PORT = "4000";
          OPENCODE_ENDPOINT = "http://MegamanX.local:4000";
        };

        environment.shellAliases = {
          llm-status = "curl http://MegamanX.local:4000/status";
        };
      };
    };

    llm-claude = {
      packages = with pkgs; [
        claude-code
      ];

      enableAgentSkills = true;

      config = {
        environment.sessionVariables = {
          CLAUDE_API_BASE = "http://MegamanX.local:4000";
        };
      };
    };

    llm-host = {
      packages = with pkgs; [
        ollama
      ];

      config = {};
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
        colima
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
