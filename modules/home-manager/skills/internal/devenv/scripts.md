# Devenv Scripts

Define custom scripts available in your development environment.

## Basic Script

```nix
{ pkgs, ... }:

{
  packages = [ pkgs.curl pkgs.jq ];

  scripts.fetch-json.exec = ''
    curl "https://httpbin.org/get?$1" | jq '.args'
  '';
}
```

```bash
$ devenv shell
(devenv) $ fetch-json foo=1
{
  "foo": "1"
}
```

## Forwarding Arguments

```nix
scripts.foo.exec = ''
  npx @foo/cli "$@";
'';
```

## Runtime Packages

Packages available only when script runs (not in global env):

```nix
scripts.analyze-json = {
  exec = ''
    curl "https://httpbin.org/get?$1" | jq '.args'
  '';
  packages = [ pkgs.curl pkgs.jq ];
  description = "Fetch and analyze JSON";
};
```

## Pinning Packages in Script

Reference package paths directly:

```nix
scripts.fetch-data.exec = ''
  ${pkgs.curl}/bin/curl "https://example.com/api" | ${pkgs.jq}/bin/jq '.'
'';
```

## Using Other Languages

```nix
{ pkgs, config, ... }:

{
  scripts.python-hello = {
    exec = ''
      print("Hello from Python!")
    '';
    package = config.languages.python.package;
    description = "Hello world in Python";
  };

  scripts.nu-greet = {
    exec = ''
      def greet [name] {
        ["hello" $name]
      }
      greet "world"
    '';
    package = pkgs.nushell;
    binary = "nu";
    description = "Greet in Nushell";
  };
}
```

## External Script Files

```nix
scripts.setup = {
  exec = ./scripts/setup.sh;
  description = "Run setup script";
};
```

## Displaying Available Scripts

```nix
{ pkgs, config, lib, ... }:

{
  enterShell = ''
    echo "Available scripts:"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: script: 
        "echo '  ${name} - ${script.description or ""}'"
      ) config.scripts
    )}
  '';
}
```

Or use a more formatted approach:

```nix
enterShell = ''
  echo
  echo "Helper scripts:"
  ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t
  ${lib.generators.toKeyValue {} (lib.mapAttrs (name: value: value.description or "") config.scripts)}
  EOF
  echo
'';
```

## Script vs Task

| Feature | Script | Task |
|---------|--------|------|
| Available as command | Yes | Via `devenv tasks run` |
| Dependencies | No | Yes (`before`/`after`) |
| Inputs/Outputs | No | Yes (JSON) |
| File watching | No | Yes (`execIfModified`) |
| Status check | No | Yes (`status`) |

**Use scripts for:** Simple commands, aliases, utilities
**Use tasks for:** Build steps, setup procedures, anything with dependencies
