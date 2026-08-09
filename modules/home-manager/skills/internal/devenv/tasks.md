# Devenv Tasks

Tasks allow dependency management between code operations, executed in parallel.

## Quick Reference

| Command | Purpose |
|---------|---------|
| `devenv tasks run <task>` | Run specific task |
| `devenv tasks run <namespace>` | Run all tasks in namespace |

## Defining Tasks

```nix
{ pkgs, ... }:

{
  tasks."myapp:hello" = {
    exec = ''echo "Hello, world!"'';
  };
}
```

```bash
$ devenv tasks run myapp:hello
Running tasks     myapp:hello
Succeeded         myapp:hello         9ms
```

Run all tasks in namespace:
```bash
$ devenv tasks run myapp
# Runs myapp:hello, myapp:build, myapp:test, etc.
```

## Run on Shell Entry

```nix
tasks."setup:env" = {
  exec = "echo 'Setting up environment'";
  before = [ "devenv:enterShell" "devenv:enterTest" ];
};
```

## Using Different Languages

```nix
tasks."python:hello" = {
  exec = ''
    print("Hello from Python!")
  '';
  package = config.languages.python.package;
};
```

## Status Checks (Skip Expensive Tasks)

```nix
tasks."myapp:migrations" = {
  exec = "db-migrate";
  status = "db-needs-migrations";  # If exits 0, skip exec
};
```

## File-Based Execution

Only run when files change:

```nix
tasks."myapp:build" = {
  exec = "npm run build";
  execIfModified = [
    "src/**/*.ts"
    "*.json"
    "package.json"
  ];
  cwd = "./frontend";
};
```

## Inputs and Outputs

Tasks can pass data via JSON:

```nix
tasks."myapp:task" = {
  exec = ''
    echo $DEVENV_TASK_INPUT > $DEVENV_ROOT/input.json
    echo '{ "output": 1 }' > $DEVENV_TASK_OUTPUT_FILE
    echo $DEVENV_TASKS_OUTPUTS > $DEVENV_ROOT/outputs.json
  '';
  input = {
    value = 1;
  };
};
```

**Environment variables:**
- `$DEVENV_TASK_INPUT` - JSON object of task's input
- `$DEVENV_TASKS_OUTPUTS` - JSON object with dependent task outputs
- `$DEVENV_TASK_OUTPUT_FILE` - Write task output here

### CLI Input Override

```bash
# Individual values (auto-parsed as JSON)
devenv tasks run myapp:task --input value=42 --input name=hello

# Full JSON object
devenv tasks run myapp:task --input-json '{"value": 42}'
```

## Dependencies

```nix
tasks."app:test" = {
  exec = "npm test";
  after = [ "app:build" ];  # Wait for build to succeed
};
```

**Dependency suffixes:**
- `@started` - wait for task to begin
- `@succeeded` (default) - wait for exit code 0
- `@completed` - wait for finish regardless of exit code

## Processes as Tasks

All processes available with `devenv:processes:` prefix:

```nix
# Setup before process starts
tasks."app:setup" = {
  exec = "echo 'Preparing...'";
  before = [ "devenv:processes:web-server" ];
};

# Cleanup after process stops
tasks."app:cleanup" = {
  exec = "rm -rf ./tmp/cache/*";
  after = [ "devenv:processes:app-server" ];
};
```

## Git Integration (Monorepo)

```nix
{ config, ... }:

{
  tasks."build:frontend" = {
    exec = "npm run build";
    cwd = "${config.git.root}/frontend";
  };

  tasks."test:backend" = {
    exec = "cargo test";
    cwd = "${config.git.root}/backend";
  };
}
```
