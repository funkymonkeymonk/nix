{lib}: machineSpecialArgs: module: let
  withSpecialArgs = specialArgs: module: let
    callModule = module: args: let
      imported =
        if builtins.isPath module || builtins.isString module
        then import module
        else module;
      moduleArgsFor = name:
        if builtins.hasAttr name specialArgs
        then builtins.getAttr name specialArgs
        else if name == "specialArgs"
        then specialArgs
        else if name == "inputs" || name == "self"
        then throw "Machine module requested `${name}` outside its constructor special arguments"
        else if builtins.hasAttr name args
        then builtins.getAttr name args
        else if builtins.hasAttr name (args.specialArgs or {})
        then builtins.getAttr name args.specialArgs
        else builtins.getAttr name args.config._module.args;
      moduleArgs =
        builtins.removeAttrs args ["inputs" "self" "specialArgs"]
        // builtins.removeAttrs (args.specialArgs or {}) ["inputs" "self"]
        // specialArgs
        // builtins.mapAttrs (name: _: moduleArgsFor name) (builtins.functionArgs imported)
        // {inherit specialArgs;};
      evaluated =
        if builtins.isFunction imported
        then imported moduleArgs
        else imported;
    in
      if builtins.isAttrs evaluated
      then
        evaluated
        // lib.optionalAttrs (builtins.hasAttr "imports" evaluated) {
          imports = map (withSpecialArgs specialArgs) evaluated.imports;
        }
        // lib.optionalAttrs (builtins.isPath module || builtins.isString module) {
          _file = toString module;
        }
      else evaluated;
  in
    if builtins.isFunction module || builtins.isPath module || builtins.isString module
    then ({specialArgs ? {}, ...} @ args: callModule module (args // {inherit specialArgs;}))
    else if builtins.isAttrs module && builtins.hasAttr "imports" module
    then module // {imports = map (withSpecialArgs specialArgs) module.imports;}
    else module;
in
  withSpecialArgs machineSpecialArgs module
