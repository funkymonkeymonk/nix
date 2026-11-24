{pkgs}:
pkgs.runCommand "test-media-library-status" {
  nativeBuildInputs = [pkgs.python3];
} ''
  cd ${../.}
  python tests/test-media-library-status.py
  touch $out
''
