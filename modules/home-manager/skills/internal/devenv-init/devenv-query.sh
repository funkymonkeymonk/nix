#!/usr/bin/env bash
# Query devenv options and packages
# Usage: devenv-query.sh [options|packages|eval] <query>
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/devenv-init"
CACHE_TTL=86400  # 24 hours

mkdir -p "$CACHE_DIR"

usage() {
    cat << 'EOF'
Usage: devenv-query.sh <command> <query>

Commands:
  options <pattern>   Search devenv options (e.g., "languages.rust", "services.postgres")
  packages <name>     Search nixpkgs packages
  eval <attr>         Evaluate attribute in current devenv.nix (returns JSON)
  langs               List all available language options
  services            List all available service options

Examples:
  devenv-query.sh options languages.rust
  devenv-query.sh packages ripgrep
  devenv-query.sh eval languages.rust.enable
  devenv-query.sh langs
EOF
    exit 1
}

# Cache helper
cache_get() {
    local key="$1"
    local file="$CACHE_DIR/$key"
    if [[ -f "$file" ]]; then
        local age=$(($(date +%s) - $(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)))
        if [[ $age -lt $CACHE_TTL ]]; then
            cat "$file"
            return 0
        fi
    fi
    return 1
}

cache_set() {
    local key="$1"
    local file="$CACHE_DIR/$key"
    cat > "$file"
}

# Search options using devenv's option documentation
search_options() {
    local pattern="$1"
    local cache_key="options_${pattern//\//_}"
    
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    # Use devenv repl to query options (more reliable than search TUI)
    # Fall back to known patterns if repl fails
    local result
    result=$(devenv eval "builtins.attrNames config.${pattern%.*}" 2>/dev/null | tr -d '[]"' | tr ',' '\n' | grep -v '^$' || true)
    
    if [[ -z "$result" ]]; then
        # Provide known options for common patterns
        case "$pattern" in
            languages.rust*)
                result="enable channel components rustfmt"
                ;;
            languages.python*)
                result="enable version venv package libraries uv"
                ;;
            languages.javascript*)
                result="enable npm yarn pnpm bun corepack"
                ;;
            languages.go*)
                result="enable package"
                ;;
            languages*)
                result="rust python javascript typescript go java ruby php c cplusplus zig nim elixir erlang haskell scala clojure kotlin swift dart julia r lua perl"
                ;;
            services.postgres*)
                result="enable package port listen_addresses initialDatabases initialScript"
                ;;
            services.redis*)
                result="enable package port bind"
                ;;
            services.mysql*)
                result="enable package port"
                ;;
            services*)
                result="postgres redis mysql mongodb elasticsearch rabbitmq minio nginx caddy"
                ;;
            scripts*)
                result="<name>.exec <name>.description"
                ;;
            tasks*)
                result="<name>.exec <name>.after <name>.before"
                ;;
            processes*)
                result="<name>.exec <name>.process-compose"
                ;;
            pre-commit.hooks*)
                result="rustfmt clippy ruff black mypy prettier eslint gofmt"
                ;;
            *)
                result="packages languages services scripts tasks processes pre-commit enterShell enterTest"
                ;;
        esac
    fi
    
    echo "$result" | cache_set "$cache_key"
    echo "$result"
}

# Search packages
search_packages() {
    local name="$1"
    local cache_key="packages_${name//\//_}"
    
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    # devenv search outputs to TUI, so we use nix search instead
    local result
    result=$(nix search nixpkgs "$name" --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for k, v in list(data.items())[:10]:
    name = k.split('.')[-1]
    desc = v.get('description', '')[:60]
    print(f'{name}: {desc}')
" 2>/dev/null || echo "Search requires nix with flakes enabled")
    
    echo "$result" | cache_set "$cache_key"
    echo "$result"
}

# Evaluate attribute
eval_attr() {
    local attr="$1"
    devenv eval "$attr" 2>/dev/null || echo "{\"error\": \"Failed to evaluate $attr\"}"
}

# List all languages
list_langs() {
    local cache_key="all_languages"
    
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    local result="Available languages in devenv:

| Language | Option | Key Settings |
|----------|--------|--------------|
| Rust | languages.rust | enable, channel (stable/beta/nightly), components |
| Python | languages.python | enable, version, venv.enable, uv.enable |
| JavaScript | languages.javascript | enable, npm.enable, pnpm.enable, yarn.enable |
| TypeScript | languages.typescript | enable |
| Go | languages.go | enable, package |
| Java | languages.java | enable, jdk.package |
| Ruby | languages.ruby | enable, version |
| PHP | languages.php | enable, version |
| C/C++ | languages.c, languages.cplusplus | enable |
| Zig | languages.zig | enable |
| Elixir | languages.elixir | enable |
| Haskell | languages.haskell | enable |
| Scala | languages.scala | enable |
| Kotlin | languages.kotlin | enable |
| Swift | languages.swift | enable |
| Dart | languages.dart | enable |
| Julia | languages.julia | enable |
| R | languages.r | enable |
| Lua | languages.lua | enable |
| Perl | languages.perl | enable |
| Nim | languages.nim | enable |
| OCaml | languages.ocaml | enable |
| Deno | languages.deno | enable |
| Gleam | languages.gleam | enable |
| Unison | languages.unison | enable |
| V | languages.v | enable |

Example:
  languages.rust = {
    enable = true;
    channel = \"stable\";  # or \"beta\", \"nightly\"
  };"
    
    echo "$result" | cache_set "$cache_key"
    echo "$result"
}

# List all services
list_services() {
    local cache_key="all_services"
    
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    local result="Available services in devenv:

| Service | Option | Key Settings |
|---------|--------|--------------|
| PostgreSQL | services.postgres | enable, port, listen_addresses, initialDatabases |
| MySQL | services.mysql | enable, port |
| Redis | services.redis | enable, port, bind |
| MongoDB | services.mongodb | enable, port |
| Elasticsearch | services.elasticsearch | enable |
| RabbitMQ | services.rabbitmq | enable, port |
| MinIO | services.minio | enable |
| Nginx | services.nginx | enable, httpConfig |
| Caddy | services.caddy | enable, config |
| Mailhog | services.mailhog | enable |
| Adminer | services.adminer | enable |
| Blackfire | services.blackfire | enable |
| Memcached | services.memcached | enable |
| WireMock | services.wiremock | enable |

Example:
  services.postgres = {
    enable = true;
    port = 5432;
    initialDatabases = [{ name = \"mydb\"; }];
  };"
    
    echo "$result" | cache_set "$cache_key"
    echo "$result"
}

# Main
case "${1:-}" in
    options|o)
        [[ -z "${2:-}" ]] && usage
        search_options "$2"
        ;;
    packages|p)
        [[ -z "${2:-}" ]] && usage
        search_packages "$2"
        ;;
    eval|e)
        [[ -z "${2:-}" ]] && usage
        eval_attr "$2"
        ;;
    langs|languages)
        list_langs
        ;;
    services|svc)
        list_services
        ;;
    *)
        usage
        ;;
esac
