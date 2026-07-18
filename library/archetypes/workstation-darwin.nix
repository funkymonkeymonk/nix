# Workstation Darwin archetype — personal developer workstation
#
# Lightweight LLM stack (gemma3:4b only via Ollama) designed for
# 24GB machines running other apps alongside — no heavy inference
# servers, container overlays, or gateway proxies.
{
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../modules/roles/homebrew.nix
    ../../modules/services/ollama/darwin.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      developer.enable = true;
      desktop.enable = true;
      workstation.enable = true;
      pi.enable = true;
      homebrew.enable = true;
    };

    ollama = {
      enable = lib.mkDefault true;
      host = "127.0.0.1";
      port = 11434;
    };
  };
}
