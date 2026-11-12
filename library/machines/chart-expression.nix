''
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    catalog = import ./library/machines/catalog.nix { inputs = flake.inputs; };
    action = builtins.getEnv "MACHINE_CHART_ACTION";
    selectedKind = builtins.getEnv "MACHINE_CHART_KIND";
    selectedName = builtins.getEnv "MACHINE_CHART_NAME";
    includePackages = builtins.getEnv "MACHINE_CHART_PACKAGES" != "false";
    packageError = builtins.getEnv "MACHINE_CHART_PACKAGE_NOTE";
    rootPath = toString ./.;
    machineEntries =
      map (name: {kind = "nixos"; inherit name;}) (builtins.attrNames flake.nixosConfigurations)
      ++ map (name: {kind = "darwin"; inherit name;}) (builtins.attrNames flake.darwinConfigurations);
    machine = builtins.getAttr selectedName catalog;
    configuration = builtins.getAttr selectedName (
      if selectedKind == "nixos" then flake.nixosConfigurations else flake.darwinConfigurations
    );
    config = configuration.config;
    packageName = package: package.pname or package.name;
    node = label: children: {inherit label children;};
    relativeSource = source:
      let
        storePath = builtins.match "^/nix/store/[^/]+/(.*)$" source;
      in
        if lib.hasPrefix (rootPath + "/") source
        then lib.removePrefix (rootPath + "/") source
        else if storePath == null then source else builtins.head storePath;
    installerLabel = source:
      if source == "<unknown-file>"
      then "Inline machine configuration"
      else if lib.hasPrefix "modules/roles/" source
      then "Role: " + lib.removeSuffix ".nix" (builtins.baseNameOf source) + " (" + source + ")"
      else if lib.hasPrefix "library/archetypes/" source
      then "Archetype: " + lib.removeSuffix ".nix" (builtins.baseNameOf source)
      else source;
    renderNodes = prefix: nodes:
      lib.concatStringsSep "\n" (lib.imap0 (index: entry:
        let
          isLast = index == builtins.length nodes - 1;
          branch = if isLast then "└── " else "├── ";
          childPrefix = prefix + (if isLast then "    " else "│   ");
          children =
            if entry.children == []
            then ""
            else "\n" + renderNodes childPrefix entry.children;
        in
          prefix + branch + entry.label + children
      ) nodes);
    moduleLabel = module:
      let
        path = if builtins.isPath module then relativeSource (toString module) else "<inline module>";
        isArchetype = lib.hasPrefix "library/archetypes/" path;
      in
        if path == "<inline module>"
        then "Inline catalog module"
        else if isArchetype
        then "Archetype: " + lib.removeSuffix ".nix" (builtins.baseNameOf path)
        else "Module: " + path;
    compositionNodes = map (module: node (moduleLabel module) []) machine.modules;
    enabledRoles =
      lib.sort builtins.lessThan (lib.mapAttrsToList (name: role: name)
        (lib.filterAttrs (_: role: role.enable) (config.myConfig.roles or {})));
    roleNodes = map (role: node role []) enabledRoles;
    packageDefinitions = configuration.options.environment.systemPackages.definitionsWithLocations;
    packageGroups =
      if !includePackages
      then []
      else let
        definitions = map (definition: {
          source = relativeSource (toString definition.file);
          packages = map packageName definition.value;
        }) packageDefinitions;
        sources = lib.filter (source:
          lib.any (definition: definition.source == source && definition.packages != []) definitions
        ) (lib.sort builtins.lessThan (lib.unique (map (definition: definition.source) definitions)));
      in
        map (source:
          let
            packages = lib.unique (lib.concatLists (map (definition: definition.packages)
              (lib.filter (definition: definition.source == source) definitions)));
          in
            node (installerLabel source) (map (package: node package []) (lib.sort builtins.lessThan packages))
        ) sources;
    homebrewPackageName = package: if builtins.isString package then package else package.name;
    homebrewGroups =
      if selectedKind != "darwin" || !includePackages
      then []
      else let
        homebrewOptions = configuration.options.homebrew or {};
        collectGroups =
          label: definitions: getPackages: let
            normalized = map (definition: {
              source = relativeSource (toString definition.file);
              packages = getPackages definition.value;
            }) definitions;
            sources = lib.filter (source:
              lib.any (definition: definition.source == source && definition.packages != []) normalized
            ) (lib.sort builtins.lessThan (lib.unique (map (definition: definition.source) normalized)));
          in
            map (source:
              let
                packages = lib.unique (lib.concatLists (map (definition: definition.packages)
                  (lib.filter (definition: definition.source == source) normalized)));
              in
                node (label + " (" + source + ")")
                  (map (package: node package []) (lib.sort builtins.lessThan packages))
            ) sources;
        listPackages = value: map homebrewPackageName value;
        appStorePackages = value: builtins.attrNames value;
      in
        collectGroups "Formulae" homebrewOptions.brews.definitionsWithLocations listPackages
        ++ collectGroups "Casks" homebrewOptions.casks.definitionsWithLocations listPackages
        ++ collectGroups "Mac App Store apps" homebrewOptions.masApps.definitionsWithLocations appStorePackages;
    homeUsers = if includePackages then (config.home-manager.users or {}) else {};
    homeNodes = lib.mapAttrsToList (user: homeConfig:
      node ("Home Manager (" + user + ")")
        (map (package: node package []) (lib.sort builtins.lessThan
          (lib.unique (map packageName (homeConfig.home.packages or [])))))
    ) homeUsers;
    serviceOptions = config.services or {};
    openssh = serviceOptions.openssh or {};
    tailscale = serviceOptions.tailscale or {};
    systemServices =
      (if openssh.enable or false then {openssh = {name = "OpenSSH"; port = 22;};} else {})
      // (if tailscale.enable or false then {tailscale = {name = "Tailscale"; port = 0;};} else {});
    serviceRegistry = config.myConfig.serviceRegistry or {};
    services = systemServices // lib.mapAttrs (_: service: {
      inherit (service) name port;
    }) serviceRegistry;
    serviceNodes = lib.mapAttrsToList (_: service:
      node (service.name + (if service.port > 0 then " (port " + toString service.port + ")" else "")) []
    ) services;
    sections = lib.filter (section: section.children != []) ([
      (node "Catalog composition" compositionNodes)
      (node "Enabled roles" roleNodes)
      (node "System packages (grouped by installer)" packageGroups)
      (node "Homebrew packages" homebrewGroups)
      (node "Home Manager packages" homeNodes)
      (node "Managed services" serviceNodes)
    ] ++ lib.optional (packageError != "")
      (node "Package lists unavailable" [(node packageError [])]));
    chart = selectedName + " (" + (config.networking.hostName or selectedName)
      + ", " + configuration.pkgs.stdenv.hostPlatform.system + ")"
      + (if sections == [] then "" else "\n" + renderNodes "" sections);
  in
    if action == "names"
    then builtins.toJSON machineEntries
    else chart
''
