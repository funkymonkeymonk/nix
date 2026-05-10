# Yaks - Shared Discovery Trees CLI
# Distributed TODO list using CRDTs for conflict-free collaboration
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  openssl,
  pkg-config,
}:
rustPlatform.buildRustPackage rec {
  pname = "yaks";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "mattwynne";
    repo = "yaks";
    rev = "v${version}";
    hash = "sha256-UCwDctFEsG63x+wgOoGdC94Cxo+wEMaAjCV3mNvHVD8=";
  };

  cargoHash = "sha256-m2gqZSVdGlQPoL97hs83Rn/QNUBzwXu+GvSkB+UJRL8=";

  nativeBuildInputs = [
    installShellFiles
    pkg-config
  ];

  buildInputs = [openssl];

  # Skip tests during build - they may need git environment
  doCheck = false;

  postInstall = ''
    # Install shell completions if available
    if [ -d completions ]; then
      installShellCompletion --cmd yx \
        --bash completions/yx.bash \
        --zsh completions/_yx \
        --fish completions/yx.fish 2>/dev/null || true
    fi
  '';

  meta = with lib; {
    description = "Shared Discovery Trees in the CLI - distributed TODO list for teams of humans and robots";
    homepage = "https://github.com/mattwynne/yaks";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "yx";
  };
}
