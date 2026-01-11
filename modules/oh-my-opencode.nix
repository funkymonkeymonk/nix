{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  # Build oh-my-opencode from npm
  ohMyOpenCode = pkgs.stdenv.mkDerivation {
    pname = "oh-my-opencode";
    version = "latest";

    src = null;

    nativeBuildInputs = with pkgs; [nodejs];

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/lib/node_modules

      # Install globally via npm
      npm install -g --prefix $out oh-my-opencode

      # Symlink binaries to bin directory
      ln -sf $out/lib/node_modules/.bin/opencode $out/bin/
    '';

    meta = with pkgs.lib; {
      description = "The Best Agent Harness for OpenCode";
      homepage = "https://ohmyopencode.com/";
      license = licenses.mit;
      platforms = platforms.all;
    };
  };
in {
  config = {
    environment.systemPackages = [ohMyOpenCode];
  };
}
