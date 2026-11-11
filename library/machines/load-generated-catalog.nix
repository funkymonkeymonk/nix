{
  directory,
  existingCatalog,
  darwinMachine,
  nixosMachine,
}: let
  directoryPath = toString directory;
  directoryEntries =
    if builtins.pathExists directoryPath
    then builtins.readDir directoryPath
    else {};
  nixFiles = builtins.filter (filename:
    directoryEntries.${filename}
    == "regular"
    && builtins.stringLength filename >= 4
    && builtins.substring (builtins.stringLength filename - 4) 4 filename == ".nix")
  (builtins.attrNames directoryEntries);
  validMachineName = name:
    builtins.stringLength name
    <= 63
    && builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null;
  loadEntry = filename: let
    machineName = builtins.substring 0 (builtins.stringLength filename - 4) filename;
    sourcePath = "${directoryPath}/${filename}";
    imported = builtins.tryEval (
      let
        entryFunction = import sourcePath;
        entry =
          if builtins.isFunction entryFunction
          then entryFunction {inherit darwinMachine nixosMachine;}
          else throw "expected a function accepting { darwinMachine, nixosMachine }";
      in
        builtins.deepSeq entry entry
    );
    records =
      if imported.success
      then imported.value
      else {};
    recordNames =
      if builtins.isAttrs records
      then builtins.attrNames records
      else [];
    record =
      if builtins.length recordNames == 1
      then builtins.getAttr (builtins.head recordNames) records
      else {};
    requiredRecordFields = [
      "builder"
      "extraSpecialArgs"
      "hostname"
      "kind"
      "modules"
      "overrides"
      "secretProfile"
      "system"
    ];
    validRecord =
      builtins.isAttrs record
      && builtins.all (field: builtins.hasAttr field record) requiredRecordFields
      && builtins.elem record.kind ["darwin" "nixos"]
      && builtins.isString record.builder
      && builtins.isString record.hostname
      && builtins.isString record.secretProfile
      && builtins.isString record.system
      && builtins.isList record.modules
      && builtins.isAttrs record.extraSpecialArgs
      && builtins.isAttrs record.overrides;
  in
    if !validMachineName machineName
    then throw "generated machine catalog filename '${filename}' has an invalid machine name"
    else if !imported.success
    then throw "generated machine catalog entry '${filename}' could not be evaluated; expected a Nix function accepting { darwinMachine, nixosMachine } and returning one machine record"
    else if !builtins.isAttrs records || builtins.length recordNames != 1
    then throw "generated machine catalog entry '${filename}' must return exactly one machine record"
    else if builtins.head recordNames != machineName
    then throw "generated machine catalog filename '${filename}' does not match returned machine name '${builtins.head recordNames}'"
    else if !validRecord
    then throw "generated machine catalog entry '${filename}' has an unsupported machine record shape"
    else {
      name = machineName;
      value = record;
    };
  generatedCatalog = builtins.listToAttrs (map loadEntry nixFiles);
  collisions = builtins.filter (name: builtins.hasAttr name existingCatalog) (builtins.attrNames generatedCatalog);
in
  if collisions != []
  then throw "generated machine catalog collision: '${builtins.head collisions}' already exists in the hand-maintained catalog"
  else generatedCatalog
