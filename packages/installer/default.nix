{
  pkgs,
  lib,
  stdenv,
  ...
}:
stdenv.mkDerivation rec {
  pname = "nixos-flake-installer";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    bun
  ];

  buildInputs = with pkgs; [
    bun
  ];

  buildPhase = ''
    export HOME=$TMPDIR

    # Install dependencies
    bun install --frozen-lockfile || bun install

    # Build the standalone executable
    bun build ./src/index.tsx \
      --outfile ./nixos-flake-installer \
      --target node \
      --bundle \
      --external react \
      --external ink \
      --external ink-text-input \
      --external ink-select-input
  '';

  installPhase = ''
        mkdir -p $out/bin

        # Create wrapper script that uses bun to run the bundled code
        cat > $out/bin/nixos-flake-installer << 'EOF'
    #!/usr/bin/env bash
    exec ${pkgs.bun}/bin/bun run ${placeholder "out"}/lib/nixos-flake-installer/dist/index.js "$@"
    EOF
        chmod +x $out/bin/nixos-flake-installer

        # Install the source and node_modules
        mkdir -p $out/lib/nixos-flake-installer
        cp -r . $out/lib/nixos-flake-installer/
  '';

  dontStrip = true;

  meta = with lib; {
    description = "Interactive NixOS installer with TUI for funkymonkeymonk/nix flake";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "nixos-flake-installer";
  };
}
