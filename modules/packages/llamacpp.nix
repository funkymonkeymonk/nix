{
  stdenv,
  fetchFromGitHub,
  cmake,
  python3,
  blas,
  openblas,
  protobuf,
}:
stdenv.mkDerivation rec {
  pname = "llamacpp";
  version = "b3531";

  src = fetchFromGitHub {
    owner = "ggerganov";
    repo = "llama.cpp";
    rev = "b3531b9c0c8bf5f4b6e4b4b4b4b4b4b4b4b4b4b4";
    sha256 = "sha256-1g3x8q9z7v6j5k4m2n3l1p0o9r8t7w6e5y4u3i2o1p0q9r8t7w6e5y4u3i2o1";
  };

  nativeBuildInputs = [cmake python3];
  buildInputs = [blas openblas protobuf];

  cmakeFlags = [
    "-DLLAMA_METAL=ON" # Apple Silicon GPU acceleration
    "-DLLAMA_BLAS=ON"
    "-DLLAMA_BLAS_VENDOR=OpenBLAS"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share
    cp bin/llama-server $out/bin/
    cp bin/llama-cli $out/bin/
    cp -r models $out/share/
  '';

  meta = with stdenv.lib; {
    description = "LLM inference in C/C++";
    homepage = "https://github.com/ggerganov/llama.cpp";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
