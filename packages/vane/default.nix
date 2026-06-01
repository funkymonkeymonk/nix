# Vane AI-powered answering engine (Next.js app with standalone output)
#
# To compute npmDepsHash:
#   1. Generate package-lock.json from yarn.lock locally (or use npm install --package-lock-only)
#   2. Set npmDepsHash = lib.fakeHash; and build
#   3. Nix will fail with the actual hash — copy it here
#   4. Rebuild with the correct hash
{
  buildNpmPackage,
  nodejs,
  fetchFromGitHub,
  python3,
  makeWrapper,
  lib,
  ...
}:

buildNpmPackage rec {
  pname = "vane";
  version = "1.12.2";

  src = fetchFromGitHub {
    owner = "ItzCrazyKns";
    repo = "Vane";
    rev = "v${version}";
    hash = "sha256-mQx2ZTUkTRbtcOZciyRpjH6G391oslAXRzjWBO1NKg8=";
  };

  npmDepsHash = "sha256-zG2gS6PVx4HfK49y4ylbgccK2GCNs2TSAgm6huuqW9s=";

  npmFlags = ["--legacy-peer-deps"];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  preBuild = ''
    patch_file="src/app/layout.tsx"
    sed -i \
      -e "s/import { Montserrat } from .next.font.google.;/\/\/ font patched for nix build/" \
      -e "/^const montserrat = Montserrat({$/,/^});$/c\
    const montserrat = { className: \"\", style: { fontFamily: \"system-ui, sans-serif\" } };" \
      "$patch_file"
  '';

  nativeBuildInputs = [python3 makeWrapper];

  NEXT_TELEMETRY_DISABLED = 1;

  buildPhase = ''
    runHook preBuild
    # Disable Google Fonts fetch (fails in sandbox) - font falls back to system fonts
    NEXT_PUBLIC_DISABLE_GOOGLE_FONTS=1 npm run build 2>&1
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/vane $out/bin

    cp -r .next/standalone/* $out/lib/vane/
    cp -r public $out/lib/vane/
    mkdir -p $out/lib/vane/.next
    cp -r .next/static $out/lib/vane/.next/static

    makeWrapper ${nodejs}/bin/node $out/bin/vane \
      --add-flags "$out/lib/vane/server.js" \
      --chdir "$out/lib/vane" \
      --set NODE_ENV production \
      --set NEXT_TELEMETRY_DISABLED 1

    runHook postInstall
  '';

  meta = {
    description = "AI-powered answering engine with SearXNG integration";
    homepage = "https://github.com/ItzCrazyKns/Vane";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
