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

    # pi-plugins flake input, provided here (not in modules/roles/pi.nix) so
    # the role module itself doesn't need `inputs` directly — mirrors
    # skills.superpowersPath above. Override per-machine with a direct
    # assignment, e.g. for a local pi-plugins checkout during development.
    pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);

    ollama = {
      enable = lib.mkDefault true;
      host = "127.0.0.1";
      port = 11434;
    };
  };
}
