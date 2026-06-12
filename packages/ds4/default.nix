# ds4 - DeepSeek V4 Flash/PRO local inference engine
# Metal-native C project by antirez
{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation rec {
  pname = "ds4";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "antirez";
    repo = "ds4";
    rev = "d881f2a05e8ff6bec001315a36b794b4aa310173";
    hash = "sha256-jjpQTaWfvYG0fmmPiA/pbD3YyYseyPygeCW87C5IDzI=";
  };

  enableParallelBuilding = true;

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ds4 ds4-server ds4-agent ds4-cli ds4-eval ds4-bench $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "DeepSeek V4 Flash and PRO local inference engine for Metal, CUDA and ROCm";
    homepage = "https://github.com/antirez/ds4";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
    mainProgram = "ds4";
  };
}
