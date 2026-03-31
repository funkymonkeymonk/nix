# Pi - Minimal terminal coding harness
# AI coding agent CLI with extensible skills, extensions, and themes
{
  lib,
  buildNpmPackage,
  fetchurl,
}:
buildNpmPackage rec {
  pname = "pi-coding-agent";
  version = "0.64.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@mariozechner/pi-coding-agent/-/pi-coding-agent-${version}.tgz";
    hash = "sha256-SSdIyhoK9DEa0qFNK3dAsTPcOhvhJQ/w7klVCB2kqZo=";
  };

  npmDepsHash = "sha256-Fwx5PSIWAaRtaiLKczTsuh565LobJBXloAOIQV1Hgpg=";

  # The tarball doesn't include package-lock.json, so we copy it in postPatch
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # The package is already built in dist/
  dontNpmBuild = true;

  # Make sure the CLI is executable
  postInstall = ''
    chmod +x $out/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js
  '';

  meta = with lib; {
    description = "Minimal terminal coding harness - extensible AI coding agent CLI";
    longDescription = ''
      Pi is a minimal terminal coding harness. Adapt pi to your workflows,
      not the other way around, without having to fork and modify pi internals.
      Extend it with TypeScript Extensions, Skills, Prompt Templates, and Themes.

      Features:
      - Interactive, print, JSON, and RPC modes
      - Session management with branching and compaction
      - Extensible via npm/git packages
      - Multiple LLM provider support (Anthropic, OpenAI, Google, etc.)
    '';
    homepage = "https://github.com/badlogic/pi-mono";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "pi";
    platforms = platforms.all;
  };
}
