{inputs}: {
  machine,
  includeDisko ? false,
}: let
  diskoModules =
    if includeDisko && (machine.disko or false)
    then [inputs.disko.nixosModules.disko]
    else [];
in
  diskoModules ++ machine.modules
