{
  _config,
  _pkgs,
  ...
}: {
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    #caskArgs.no_quarantine = true;
    casks = [
      "raycast" # The version in nixpkgs is out of date
      "zed"
      "zen"
      "ollama-app"
    ];
  };
}
