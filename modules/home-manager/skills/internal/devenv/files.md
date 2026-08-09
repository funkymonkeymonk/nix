# Devenv Creating Files

Declaratively create configuration files from Nix data structures.

## Supported Formats

- `json` - JSON
- `yaml` - YAML  
- `toml` - TOML
- `ini` - INI
- `text` - Plain text

## JSON Files

```nix
{
  files."config.json".json = {
    database = {
      host = "localhost";
      port = 5432;
    };
    features = [ "auth" "api" "ui" ];
  };
}
```

Creates:
```json
{
  "database": {
    "host": "localhost",
    "port": 5432
  },
  "features": ["auth", "api", "ui"]
}
```

## YAML Files

```nix
{
  files."docker-compose.yml".yaml = {
    version = "3.8";
    services = {
      web = {
        image = "nginx:latest";
        ports = [ "8080:80" ];
      };
    };
  };
}
```

## TOML Files

```nix
{
  files."config.toml".toml = {
    title = "My App Config";
    server = {
      host = "0.0.0.0";
      port = 8000;
    };
  };
}
```

## INI Files

```nix
{
  files."settings.ini".ini = {
    general = {
      debug = "true";
      log_level = "info";
    };
    database = {
      connection_string = "postgres://localhost/mydb";
    };
  };
}
```

## Text Files

```nix
{
  files."README.txt".text = ''
    This is a development environment.
    Run `devenv shell` to get started.
  '';
}
```

## Executable Files

```nix
{
  files."setup.sh" = {
    text = ''
      #!/bin/bash
      echo "Running setup..."
      npm install
    '';
    executable = true;
  };
}
```

## Subdirectories

```nix
{
  files = {
    ".config/app/settings.json".json = {
      theme = "dark";
    };

    "scripts/build.sh" = {
      text = "#!/bin/bash\nnpm run build";
      executable = true;
    };
  };
}
```

Parent directories are created automatically.

## Dynamic Content

```nix
{ config, ... }:

{
  files."app.config.json".json = {
    database_url = "postgres://localhost:5432/${config.services.postgres.initialDatabases[0].name}";
    redis_port = config.services.redis.port;
  };
}
```

## Common Use Cases

### .env Files

```nix
{
  files.".env".text = ''
    DATABASE_URL=postgres://localhost/mydb
    REDIS_URL=redis://localhost:6379
    DEBUG=true
  '';
}
```

### Editor Config

```nix
{
  files.".editorconfig".text = ''
    root = true

    [*]
    indent_style = space
    indent_size = 2
    end_of_line = lf
    charset = utf-8
    trim_trailing_whitespace = true
    insert_final_newline = true
  '';
}
```

### Tool Configuration

```nix
{
  files.".prettierrc".json = {
    semi = true;
    singleQuote = true;
    tabWidth = 2;
  };

  files."tsconfig.json".json = {
    compilerOptions = {
      target = "ES2020";
      module = "commonjs";
      strict = true;
    };
  };
}
```
