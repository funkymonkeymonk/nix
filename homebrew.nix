{
  config,
  pkgs,
  ...
}: {
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    #caskArgs.no_quarantine = true;
    casks = [
      "1password"
      "raycast" # The version in nixpkgs is out of date
      "zed"
      "zen"
      "ollama-app"
    ];
  };
}
