{
  allowUnfree = true;
  permittedInsecurePackages = [
    "electron-39.8.10"
    "google-chrome-144.0.7559.97"
    "olm-3.2.16"
  ];
  allowInsecurePredicate = attrs: let
    pname = attrs.pname or attrs.name or "";
    fullName = "${pname}-${attrs.version or ""}";
  in
    builtins.elem fullName [
      "electron-39.8.10"
      "google-chrome-144.0.7559.97"
      "olm-3.2.16"
    ];
}
