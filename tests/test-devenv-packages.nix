{pkgs, ...}: let
  packages = import ../modules/roles/devenv-packages.nix {inherit pkgs;};
  foundationPackageGroups = import ../modules/roles/foundation-packages.nix {inherit pkgs;};
  foundationPackageTest = (import ./test-packages.nix {inherit pkgs;}).foundationPackagesTest;
  packageNames = map (package: package.pname or package.name) packages;
  requiredPackages = ["gh" "jq" "jujutsu"];
  missingPackages = builtins.filter (name: !(builtins.elem name packageNames)) requiredPackages;
  devenvCliIncluded = builtins.elem pkgs.devenv packages;
  devenvFoundationPackageIncluded = builtins.elem pkgs.devenv foundationPackageGroups.common;
  devenvBuiltAgainByFoundationTest = builtins.elem pkgs.devenv foundationPackageTest.nativeBuildInputs;
  rejectedPackages = ["himalaya" "himalaya-tui"];
  installedRejectedPackages = builtins.filter (name: builtins.elem name packageNames) rejectedPackages;
in
  assert missingPackages == [];
  assert devenvCliIncluded;
  assert devenvFoundationPackageIncluded;
  assert !devenvBuiltAgainByFoundationTest;
  assert installedRejectedPackages == [];
    pkgs.runCommand "test-devenv-packages" {} ''
      echo "Repository development shell keeps its essential CLI tools and excludes email clients"
      touch $out
    ''
