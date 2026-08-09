# Devenv Processes

Connect to and monitor devenv processes running in the current repository.

## Quick Reference

| Task | Command |
|------|---------|
| Start all processes | `devenv up` (foreground) |
| Start background | `devenv up -d` |
| Start specific process | `devenv up <name>` |
| Stop processes | `devenv processes down` |
| Wait for ready | `devenv processes wait` |

## Process Configuration

```nix
# Basic process
processes.myapp.exec = "npm run dev";

# With working directory
processes.backend = {
  exec = "cargo run";
  cwd = "./backend";
};

# With dependencies
processes.api = {
  exec = "python server.py";
  after = [ "devenv:processes:database" ];
};

# With health check
processes.web = {
  exec = "node server.js";
  ready = {
    http.get = { port = 3000; path = "/health"; };
  };
};

# With restart policy
processes.worker = {
  exec = "worker --queue jobs";
  restart = {
    on = "always";  # on_failure (default), always, never
    max = 10;       # null for unlimited
  };
};

# With file watching
processes.backend = {
  exec = "cargo run";
  watch = {
    paths = [ ./src ];
    extensions = [ "rs" "toml" ];
    ignore = [ "target" "*.log" ];
  };
};
```

## Dependency Suffixes

For **process** dependencies in `after`:
- `@started` - wait for process to begin
- `@ready` (default) - wait for readiness probe
- `@completed` - wait for process to finish

For **task** dependencies:
- `@started` - wait for task to begin
- `@succeeded` (default) - wait for exit code 0
- `@completed` - wait for task to finish

## Finding Logs

Log locations depend on the **process manager**:

### Native (Default in 2.0)

Logs go to stdout/stderr. For detached mode:
- Check `$DEVENV_STATE/` for process logs
- Run `devenv up` without `-d` to see output

### Process-Compose

```nix
process.manager.implementation = "process-compose";
```

```bash
# Via socket (default enabled)
process-compose -u $DEVENV_RUNTIME/pc.sock logs <process>
process-compose -u $DEVENV_RUNTIME/pc.sock attach <process>
process-compose -u $DEVENV_RUNTIME/pc.sock status
```

### Overmind

```nix
process.manager.implementation = "overmind";
```

```bash
overmind connect <process>
overmind logs <process>
```

## Checking Status

```bash
# Check running processes
ps aux | grep -E "devenv|process-compose" | head -5

# Check for process-compose socket
ls $DEVENV_RUNTIME/pc.sock 2>/dev/null

# Check specific port
lsof -i :<port>
```

## Debugging

1. **Check devenv environment is active:**
   ```bash
   echo $DEVENV_ROOT  # Should show project path
   ```

2. **Run process manually:**
   ```bash
   # Find command in devenv.nix
   grep -A 5 "processes.<name>" devenv.nix
   # Run directly to see errors
   ```

3. **Verbose mode:**
   ```bash
   devenv up --verbose
   ```

4. **Port conflicts:**
   ```bash
   lsof -i :<port>
   # Or use --strict-ports to fail fast
   devenv up --strict-ports
   ```

## Processes as Tasks

All processes are available as tasks with `devenv:processes:` prefix:

```nix
# Task runs before process
tasks."app:setup" = {
  exec = "echo 'Setting up...'";
  before = [ "devenv:processes:web-server" ];
};

# Task runs after process stops
tasks."app:cleanup" = {
  exec = "rm -f ./server.pid";
  after = [ "devenv:processes:app-server" ];
};
```

## Service-Specific Logs

| Service | Log Location |
|---------|--------------|
| PostgreSQL | `$DEVENV_STATE/postgres/` |
| MySQL | `$DEVENV_STATE/mysql/` |
| Redis | stdout |
| Nginx | `$DEVENV_STATE/nginx/` |
