# Devenv Services

Services are pre-configured process definitions for common software like databases.

## Quick Reference

```nix
# Enable a service
services.postgres.enable = true;

# Start services
$ devenv up
```

Services persist state to `$DEVENV_STATE/<service>/`.

## Available Services

| Service | Option Prefix |
|---------|---------------|
| PostgreSQL | `services.postgres` |
| MySQL | `services.mysql` |
| Redis | `services.redis` |
| MongoDB | `services.mongodb` |
| Elasticsearch | `services.elasticsearch` |
| Kafka | `services.kafka` |
| RabbitMQ | `services.rabbitmq` |
| Nginx | `services.nginx` |
| Caddy | `services.caddy` |
| Memcached | `services.memcached` |
| MinIO | `services.minio` |
| Vault | `services.vault` |
| ClickHouse | `services.clickhouse` |
| Prometheus | `services.prometheus` |

Full list: https://devenv.sh/services/

## PostgreSQL Example

```nix
{ pkgs, ... }:

{
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_15;
    initialDatabases = [{ name = "mydb"; }];
    extensions = extensions: [
      extensions.postgis
      extensions.timescaledb
    ];
    settings.shared_preload_libraries = "timescaledb";
    initialScript = "CREATE EXTENSION IF NOT EXISTS timescaledb;";
  };
}
```

## Redis Example

```nix
{
  services.redis = {
    enable = true;
    port = 6379;
  };
}
```

## MySQL Example

```nix
{
  services.mysql = {
    enable = true;
    initialDatabases = [{ name = "myapp"; }];
    ensureUsers = [
      {
        name = "myapp";
        password = "secret";
        ensurePermissions = {
          "myapp.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };
}
```

## Running in Background

```bash
$ devenv up -d
```

## Resetting Service State

When changing `initialScript` or `initialDatabases`, delete state:

```bash
rm -rf .devenv/state/postgres
devenv up
```

## Connecting to Services

Services typically bind to localhost. Check devenv.nix for ports:

```bash
# PostgreSQL (default 5432)
psql -h localhost -d mydb

# Redis (default 6379)
redis-cli

# MySQL (default 3306)
mysql -h localhost -u root mydb
```

## Service Logs

| Service | Log Location |
|---------|--------------|
| PostgreSQL | `$DEVENV_STATE/postgres/` |
| MySQL | `$DEVENV_STATE/mysql/` |
| MongoDB | `$DEVENV_STATE/mongodb/` |
| Elasticsearch | `$DEVENV_STATE/elasticsearch/` |

Or run `devenv up` without `-d` to see all logs in terminal.

## Common Patterns

### Multiple Databases

```nix
services.postgres = {
  enable = true;
  initialDatabases = [
    { name = "app_dev"; }
    { name = "app_test"; }
  ];
};
```

### Custom Configuration

```nix
services.postgres = {
  enable = true;
  settings = {
    log_connections = true;
    log_statement = "all";
    max_connections = 200;
  };
};
```

### Service Dependencies

```nix
{
  services.postgres.enable = true;
  
  processes.api = {
    exec = "python server.py";
    after = [ "devenv:processes:postgres" ];
  };
}
```
