{inputs}: final: _prev: {
  devenv = inputs.devenv.packages.${final.stdenv.hostPlatform.system}.devenv;
}
