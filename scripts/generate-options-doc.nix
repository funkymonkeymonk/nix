# Generates `docs/reference/options.md` from the *loaded* `myConfig.*`
# option tree of every real system configuration in this flake.
#
# Why walk loaded configs instead of parsing files by path?
# -----------------------------------------------------------
# `myConfig.*` options are declared across `modules/common/options.nix` plus
# many owning modules (onepassword, obsidian, motd, charm, zellij, syncthing,
# llm-client, agent-user, cachix, role modules, service modules, ...). That
# set of files — and which file owns which option — changes over time as
# options migrate between `modules/common/options.nix` and their owning
# modules. Parsing specific files would make this generator fragile to that
# kind of refactor.
#
# Instead, this walks `config.options.myConfig` on every
# `darwinConfigurations.*` and `nixosConfigurations.*` target already
# defined in `flake.nix`, using `lib.optionAttrSetToDocList` — the same
# nixpkgs library function `nixosOptionsDoc` uses to build the NixOS manual.
# That function already:
#   - recurses into submodules (e.g. `myConfig.users.*.name`)
#   - renders defaults/types/descriptions consistently
#   - is completely agnostic to which file declared which option
#
# Because every currently-loaded target is walked and results are
# deduplicated by option path, the generator is immune to options moving
# between files (including a concurrent migration of option domains out of
# modules/common/options.nix into owning modules) and immune to new targets
# adding options — the doc just picks them up.
{
  lib,
  self,
}: let
  # Every configuration that declares the `myConfig` namespace. Configs that
  # don't (e.g. a bare ISO image target with no myConfig import) are skipped
  # rather than erroring, so adding a minimal future target doesn't require
  # updating this generator.
  hasMyConfig = cfg: (cfg.options.myConfig or null) != null;

  allConfigs =
    (lib.attrValues (self.darwinConfigurations or {}))
    ++ (lib.attrValues (self.nixosConfigurations or {}));

  optionRoots = map (cfg: cfg.options.myConfig) (lib.filter hasMyConfig allConfigs);

  # Flatten every root into a doc-list: {loc, name, type, description,
  # default, readOnly, ...}. Recurses into submodules automatically.
  rawDocs = lib.concatMap lib.optionAttrSetToDocList optionRoots;

  visibleDocs = lib.filter (o: (o.visible or true) && !(o.internal or false)) rawDocs;

  # The same option is declared once but shows up once per config that
  # imports it (e.g. `myConfig.onepassword.enable` is loaded by every
  # target). Keep a single entry per dotted path.
  dedupedByName = lib.mapAttrsToList (_: opts: builtins.head opts) (lib.groupBy (o: o.name) visibleDocs);

  sortedDocs = lib.sort (a: b: a.name < b.name) dedupedByName;

  # First path segment after "myConfig" — used as the doc's section grouping.
  domainOf = doc: builtins.elemAt doc.loc 1;

  groupedByDomain = lib.groupBy domainOf sortedDocs;

  # ---------------------------------------------------------------------
  # Rendering helpers
  # ---------------------------------------------------------------------

  # Collapse all whitespace (including newlines from multi-line
  # descriptions/defaults) into single spaces so values fit in a markdown
  # table cell.
  oneLine = s:
    lib.concatStringsSep " " (
      lib.filter (x: x != "") (
        lib.splitString " " (lib.replaceStrings ["\n" "\r" "\t"] [" " " " " "] s)
      )
    );

  # Markdown table cells can't contain a literal "|".
  escapeCell = lib.replaceStrings ["|"] ["\\|"];

  renderType = doc: escapeCell (oneLine doc.type);

  renderDescription = doc: let
    d = doc.description or null;
  in
    if d == null || d == ""
    then "—"
    else escapeCell (oneLine d);

  renderDefault = doc:
    if doc.readOnly or false
    then "*(read-only)*"
    else if doc ? default
    then "`${escapeCell (oneLine (doc.default.text or (builtins.toJSON doc.default)))}`"
    else "*required*";

  # Section headings use the full `myConfig.<domain>` path; table rows use
  # the path relative to the domain (e.g. `enable` instead of
  # `myConfig.onepassword.enable`) to keep the table readable — except for
  # the domain's own top-level option (e.g. `myConfig.vllmMlx` itself, a
  # submodule), which is rendered as `(self)` since there's nothing to
  # strip and the section heading already states the full path.
  relativeName = domain: name: let
    prefix = "myConfig.${domain}";
  in
    if name == prefix
    then "(self)"
    else lib.removePrefix "${prefix}." name;

  renderOptionRow = domain: doc: "| \`${relativeName domain doc.name}\` | ${renderType doc} | ${renderDefault doc} | ${renderDescription doc} |";

  renderDomainSection = domain: docs: ''
    ### myConfig.${domain}

    | Option | Type | Default | Description |
    |--------|------|---------|-------------|
    ${lib.concatMapStringsSep "\n" (renderOptionRow domain) docs}
  '';

  body = lib.concatStringsSep "\n" (
    lib.mapAttrsToList renderDomainSection groupedByDomain
  );

  frontmatter = ''
    ---
    title: "Configuration Options Reference"
    description: "Complete reference for myConfig.* configuration options, auto-generated from the loaded Nix module tree"
    type: reference
    audience: both
    ---
  '';

  header = ''
    <!--
      AUTO-GENERATED — DO NOT EDIT BY HAND.

      Generated by `scripts/generate-options-doc.nix` from the *loaded*
      `myConfig.*` option tree of every darwinConfigurations/nixosConfigurations
      target in this flake, so it can never drift from the actual module
      definitions.

      Regenerate with:
        devenv tasks run docs:generate-options
    -->

    # Configuration Options Reference

    Options are declared under the `myConfig` namespace across
    `modules/common/options.nix` and the modules that own each domain
    (services, roles, home-manager modules, etc). This document reflects the
    options as they are actually loaded, not any single file's contents —
    run `devenv tasks run docs:generate-options` to refresh it after adding
    or changing a `myConfig.*` option.
  '';

  markdown = frontmatter + "\n" + header + "\n" + body + "\n";
in {
  inherit markdown;

  # Exposed for tests: the flat, deduplicated, sorted doc list this
  # generator rendered from.
  docs = sortedDocs;
}
