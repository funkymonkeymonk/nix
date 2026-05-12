# RTK - Rust Token Killer
# CLI proxy that reduces LLM token consumption by 60-90%
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.39.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-TX4MtR/rq61wxHWYJAO2x3CYvZtkCoXynf45dRC+MVo=";
  };

  cargoHash = "sha256-s3AtUftUZtzhlep8R/ZuxwmGELIZpqbQXqLTD+aS4Ro=";

  # Skip tests if they require network or specific environment
  doCheck = false;

  # Install hooks alongside the binary for Nix integration
  postInstall = ''
    mkdir -p $out/share/rtk/hooks
    if [ -d "$src/hooks" ]; then
      cp $src/hooks/*.sh $out/share/rtk/hooks/ 2>/dev/null || true
      chmod +x $out/share/rtk/hooks/*.sh 2>/dev/null || true
    fi
  '';

  meta = with lib; {
    description = "CLI proxy that reduces LLM token consumption by 60-90% on common dev commands";
    homepage = "https://github.com/rtk-ai/rtk";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "rtk";
  };
}
