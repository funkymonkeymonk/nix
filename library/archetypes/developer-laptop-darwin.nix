{inputs, ...}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      homebrew.enable = true;
      desktop.enable = true;
      entertainment.enable = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/New_York";
}
