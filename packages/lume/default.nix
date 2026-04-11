# Lume - macOS VM runtime for Apple Silicon
# https://github.com/trycua/cua/tree/main/libs/lume
{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
}:
stdenv.mkDerivation rec {
  pname = "lume";
  version = "0.3.9";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/lume-v${version}/lume-${version}-darwin-arm64.tar.gz";
    hash = "sha256-mVHP9qY+ZRsjPclM4OrcuD3+/P1JoHvdh6U07xkkEa0=";
  };

  nativeBuildInputs = [installShellFiles];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    # Install the lume binary
    install -Dm755 lume $out/bin/lume

    # Install completions if they exist
    if [ -d completions ]; then
      installShellCompletion --bash completions/lume.bash
      installShellCompletion --fish completions/lume.fish
      installShellCompletion --zsh completions/_lume
    fi

    runHook postInstall
  '';

  doCheck = false;

  meta = with lib; {
    description = "VM runtime for building AI agents, running CI/CD pipelines, and automating macOS on Apple Silicon";
    homepage = "https://cua.ai/docs/lume";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "lume";
    platforms = ["aarch64-darwin"];
  };
}
