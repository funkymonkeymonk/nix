# RTK - Rust Token Killer
# CLI proxy that reduces LLM token consumption by 60-90%
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.21.1";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-Crjzd40uzT2UAOG2gUawMRgbWFKdoeY0ecfxmlPefGM=";
  };

  cargoHash = "sha256-bLiltMM1gVSOqwI73Q+PKcDc8LQLoxzklx7urUCXW9g=";

  # Skip tests if they require network or specific environment
  doCheck = false;

  # Install hooks alongside the binary for Nix integration
  postInstall = ''
    mkdir -p $out/share/rtk/hooks
    cp $src/hooks/*.sh $out/share/rtk/hooks/
    chmod +x $out/share/rtk/hooks/*.sh
  '';

  meta = with lib; {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "rtk";
  };
}
