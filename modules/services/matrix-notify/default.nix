# Notification Router Module
# Multi-backend notification system with HTTP RPC routing
# Base module - provides scripts and options
# Import platform-specific service module separately for auto-start
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.notify;

  # Router script
  routerScript = pkgs.writeShellScriptBin "notify-router" ''
    set -e

    PORT="${toString cfg.port}"

    log() {
      echo "[$(date -Iseconds)] $*" >&2
    }

    # Matrix backend
    send_matrix() {
      local room="''${1:-}"
      local message="$2"
      local format="''${3:-text}"

      local homeserver="${cfg.backends.matrix.homeserver}"
      local access_token_file="${cfg.backends.matrix.accessTokenFile}"

      if [ -z "$homeserver" ] || [ -z "$access_token_file" ] || [ ! -f "$access_token_file" ]; then
        log "Matrix not configured properly"
        return 1
      fi

      local access_token=$(cat "$access_token_file" | tr -d '[:space:]')
      local room_id="''${room:-${cfg.backends.matrix.roomId}}"

      if [ -z "$room_id" ]; then
        log "No Matrix room ID specified"
        return 1
      fi

      local encoded_room=''${room_id//:/%3A}
      encoded_room=''${encoded_room//#/%23}

      local body
      if [ "$format" = "html" ]; then
        body="{\"msgtype\":\"m.text\",\"body\":\"$message\",\"format\":\"org.matrix.custom.html\",\"formatted_body\":\"$message\"}"
      else
        body="{\"msgtype\":\"m.text\",\"body\":\"$message\"}"
      fi

      curl -s -X POST \
        "$homeserver/_matrix/client/v3/rooms/$encoded_room/send/m.room.message/$(date +%s)" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -d "$body" > /dev/null || {
          log "Failed to send Matrix message"
          return 1
        }
    }

    # ntfy backend
    send_ntfy() {
      local topic="''${1:-}"
      local message="$2"
      local priority="''${3:-default}"

      local server="${cfg.backends.ntfy.server}"
      local default_topic="${cfg.backends.ntfy.topic}"
      local target_topic="''${topic:-$default_topic}"

      if [ -z "$server" ] || [ -z "$target_topic" ]; then
        log "ntfy not configured properly"
        return 1
      fi

      local prio_arg=""
      case "$priority" in
        high|urgent) prio_arg="-H \"Priority: urgent\"" ;;
        low) prio_arg="-H \"Priority: low\"" ;;
      esac

      curl -s -X POST "$server/$target_topic" \
        $prio_arg \
        -d "$message" > /dev/null || {
          log "Failed to send ntfy message"
          return 1
        }
    }

    # Route message to appropriate backend
    route_message() {
      local backend="$1"
      local room="$2"
      local message="$3"
      local format="$4"
      local priority="$5"

      case "$backend" in
        matrix)
          send_matrix "$room" "$message" "$format"
          ;;
        ntfy)
          send_ntfy "$room" "$message" "$priority"
          ;;
        *)
          log "Unknown backend: $backend"
          return 1
          ;;
      esac
    }

    # Simple HTTP server using netcat
    handle_request() {
      local method path body
      read -r method path _

      while IFS= read -r line; do
        line=''${line%$'\r'}
        [ -z "$line" ] && break
      done

      if [ "$method" = "POST" ]; then
        body=$(cat)
      fi

      case "$path" in
        /notify)
          if [ "$method" != "POST" ]; then
            echo -e "HTTP/1.1 405 Method Not Allowed\r\n\r\n"
            return
          fi

          local message=$(echo "$body" | ${pkgs.jq}/bin/jq -r '.message // empty')
          local backend=$(echo "$body" | ${pkgs.jq}/bin/jq -r '.backend // "${cfg.defaultBackend}"')
          local room=$(echo "$body" | ${pkgs.jq}/bin/jq -r '.room // empty')
          local format=$(echo "$body" | ${pkgs.jq}/bin/jq -r '.format // "text"')
          local priority=$(echo "$body" | ${pkgs.jq}/bin/jq -r '.priority // "normal"')

          if [ -z "$message" ]; then
            echo -e "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\n\r\n{\"error\":\"message required\"}"
            return
          fi

          if route_message "$backend" "$room" "$message" "$format" "$priority"; then
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"sent\"}"
          else
            echo -e "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\n\r\n{\"error\":\"failed to send\"}"
          fi
          ;;

        /health)
          echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}"
          ;;

        *)
          echo -e "HTTP/1.1 404 Not Found\r\n\r\n"
          ;;
      esac
    }

    log "Starting notification router on port $PORT"

    while true; do
      ${pkgs.netcat}/bin/nc -l -p "$PORT" -c handle_request || true
    done
  '';

  # Client script
  clientScript = pkgs.writeShellScriptBin "notify-send" ''
        ROUTER_URL="''${NOTIFY_ROUTER_URL:-http://localhost:${toString cfg.port}}"

        MESSAGE="$1"
        BACKEND="''${2:-${cfg.defaultBackend}}"
        ROOM="''${3:-}"
        PRIORITY="''${4:-normal}"

        if [ -z "$MESSAGE" ]; then
          MESSAGE=$(cat)
        fi

        if [ -z "$MESSAGE" ]; then
          echo "Error: No message provided" >&2
          echo "Usage: notify-send <message> [backend] [room] [priority]" >&2
          exit 1
        fi

        JSON_PAYLOAD=$(cat <<EOF
    {
      "message": "$MESSAGE",
      "backend": "$BACKEND",
      "room": "$ROOM",
      "priority": "$PRIORITY"
    }
    EOF
        )

        curl -s -X POST "$ROUTER_URL/notify" \
          -H "Content-Type: application/json" \
          -d "$JSON_PAYLOAD" || {
            echo "Error: Failed to send notification" >&2
            exit 1
          }
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [
      routerScript
      clientScript
    ];
  };
}
