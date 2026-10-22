{
  buildGoModule,
  fetchFromGitHub,
  lib,
}:
buildGoModule rec {
  pname = "ste";
  version = "0-unstable-2026-07-30";

  src = fetchFromGitHub {
    owner = "stazelabs";
    repo = "ste";
    rev = "922c9773d0004f4c40b2e1373db9ed949321373d";
    hash = "sha256-k9avMPXP+82vRDEC/AUvMCgAYDKpRrl0c0AjzTfeqII=";
  };

  vendorHash = "sha256-SAwFoIPeDPuAR1OEoKqO9B3UZ912PiZPWg8Ggy4IlfE=";
  subPackages = ["cmd/ste"];
  ldflags = ["-s" "-w" "-X" "main.version=${version}"];

  meta = {
    description = "Linter for the machine-checkable subset of ASD-STE100";
    homepage = "https://github.com/stazelabs/ste";
    license = lib.licenses.mit;
    mainProgram = "ste";
    platforms = lib.platforms.unix;
  };
}
