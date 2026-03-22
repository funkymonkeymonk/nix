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
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "mattwynne";
    repo = "yaks";
    rev = "7a8c649f9229bf49261c1aae4a59d9e5535955e7";
    hash = "sha256-DBLNytRH2+SDWtUMkxn4+YLqxeekx4agDdHYty7/M/o=";
  };

  cargoHash = "sha256-CJ6MTdpXvOgbtTvdE8yhalDq3F9lf3I8LO4bcgjSZ/c=";

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
