# Approval System Specification

## Overview

A Duo/Okta-like approval system for gating privileged operations (sudo, 1Password CLI, SSH) with phone-based push notifications requiring biometric authentication.

**Goal**: Before an AI agent or user can execute sensitive commands, a push notification is sent to the user's phone. The user must authenticate with biometric (Face ID/fingerprint) to approve or deny the request.

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         WORKSTATION                                      │
│                                                                         │
│   sudo ──► pam_privacyidea ──┐                                         │
│                              │                                          │
│   Client ─► op-gate ─────────┼──► privacyIDEA Server ◄──► SQLite       │
│               │              │    (localhost:5000)                      │
│               ▼              │              │                           │
│        1Password Connect     │              │                           │
│        (localhost:8080)      │              │                           │
│               │              │              │                           │
│   ssh ───► pam_privacyidea ──┘              │                          │
│               │                             │                           │
└───────────────┼─────────────────────────────┼───────────────────────────┘
                │                             │
                │ Sync to 1Password.com       │ Poll endpoint via Tailscale
                ▼                             ▼
        ┌───────────────┐           ┌─────────────────────┐
        │ 1Password.com │           │  pi-authenticator   │
        │ (cloud)       │           │  (forked)           │
        └───────────────┘           │                     │
                                    │  + Biometric gate   │
                                    │    before signing   │
                                    └─────────────────────┘
```

### Technology Stack

| Component | Technology | Source |
|-----------|------------|--------|
| MFA Server | privacyIDEA | Open source (AGPL) |
| Mobile App | pi-authenticator (Flutter) | Fork from privacyidea/pi-authenticator |
| PAM Module | pam_privacyidea | Open source |
| Secrets Backend | 1Password Connect | Self-hosted REST API |
| op-gate | Custom service | New (wraps Connect API) |
| Network | Tailscale | Existing infrastructure |

## privacyIDEA Server

### Role: `approval-server`

A new Nix role that deploys privacyIDEA as a local service.

### Features Used

- **Push Token**: Cryptographic challenge-response via mobile app
- **Polling Mode**: No Firebase/external server dependency
- **PAM Integration**: Native Linux PAM module
- **Event Handlers**: Customize push notification content
- **Audit Logging**: Complete record of all auth events

### Configuration Requirements

| Setting | Value | Notes |
|---------|-------|-------|
| Listen Address | `127.0.0.1:5000` | Local only, exposed via Tailscale |
| Database | SQLite | `~/.local/share/privacyidea/privacyidea.db` |
| Audit | SQLite | Same database |
| Secret Key | Generated | Stored in 1Password or secrets manager |
| Admin User | Local user | Single-user deployment |

### NixOS Module Options

```nix
services.privacyidea = {
  enable = mkEnableOption "privacyIDEA MFA server";
  
  listenAddress = mkOption {
    type = types.str;
    default = "127.0.0.1";
    description = "Address to bind the server to";
  };
  
  port = mkOption {
    type = types.port;
    default = 5000;
    description = "Port for the privacyIDEA server";
  };
  
  dataDir = mkOption {
    type = types.path;
    default = "/var/lib/privacyidea";
    description = "Directory for privacyIDEA data";
  };
  
  secretKeyFile = mkOption {
    type = types.path;
    description = "Path to file containing the secret key";
  };
  
  tailscale = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Expose server via Tailscale for mobile app access";
    };
    
    hostname = mkOption {
      type = types.str;
      description = "Tailscale hostname for this machine";
    };
  };
};
```

## PAM Integration

### Gated Commands

| Command | Integration Method | Notes |
|---------|-------------------|-------|
| `sudo` | PAM module | System-wide via `/etc/pam.d/sudo` |
| `su` | PAM module | Optional |
| SSH (server) | PAM module | If running SSH server |

### Platform-Specific PAM Configuration

#### Linux (NixOS)

```
# /etc/pam.d/sudo
auth    required    pam_privacyidea.so url=http://127.0.0.1:5000 realm=local pollTime=120
auth    include     system-auth
```

Module location: `/lib/security/pam_privacyidea.so` or `/lib64/security/pam_privacyidea.so`

#### macOS (nix-darwin)

macOS requires a ported version of the PAM module (see Decision D1).

```
# /etc/pam.d/sudo_local (survives macOS updates)
auth    sufficient  pam_privacyidea.so.2 url=http://127.0.0.1:5000 realm=local pollTime=120
```

Module location: `/usr/lib/pam/pam_privacyidea.so.2`

**Note**: macOS uses OpenPAM (BSD-based) which is API-compatible but has different:
- Module naming convention (`.so.2` suffix)
- Installation paths (`/usr/lib/pam/`)
- Build dependencies (Xcode CLT instead of `libpam0g-dev`)

### Policy Configuration

privacyIDEA policies to configure:

1. **Push notification text**: Include command context
2. **Timeout**: 5 minutes for approval
3. **Auto-approve patterns**: Safe commands that don't need approval

```python
# Example policy: push_text_on_mobile
{
    "scope": "authentication",
    "action": "push_text_on_mobile=Approve: {client_ip} requests {info}",
    "realm": "local"
}
```

## 1Password Connect Integration

### Architecture

Instead of wrapping the `op` CLI, op-gate uses **1Password Connect** as its backend. Connect is a self-hosted REST API server that provides programmatic access to 1Password vaults.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         WORKSTATION                                      │
│                                                                         │
│   Client ──► op-gate ──► privacyIDEA ──► Push Approval                 │
│                │                                                         │
│                │ (on approval)                                           │
│                ▼                                                         │
│        1Password Connect ◄──────────────────────── 1Password.com        │
│        (localhost:8080)          sync                                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Connect Instead of op CLI

| Aspect | op CLI Wrapper | 1Password Connect |
|--------|----------------|-------------------|
| Architecture | Shell wrapper, forks process | REST API, proper service |
| Performance | Process spawn per request | Persistent connection, cached |
| Error handling | Parse CLI output | Structured JSON responses |
| Session management | Complex (biometric, sessions) | Token-based, stateless |
| AI agent support | Requires Service Account workarounds | Native API access |
| Auditability | Limited | Full API access logs |

### 1Password Connect Setup

Connect requires two components deployed as containers or systemd services:

1. **connect-api**: REST API server (port 8080)
2. **connect-sync**: Syncs vault data from 1Password.com

```nix
services.onepassword-connect = {
  enable = mkEnableOption "1Password Connect server";
  
  credentialsFile = mkOption {
    type = types.path;
    description = "Path to 1password-credentials.json";
  };
  
  dataDir = mkOption {
    type = types.path;
    default = "/var/lib/onepassword-connect";
    description = "Directory for Connect data";
  };
  
  api = {
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Connect API";
    };
    
    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind API server";
    };
  };
};
```

### op-gate Service

op-gate is a service that:
1. Receives secret access requests
2. Triggers privacyIDEA push approval
3. On approval, proxies to 1Password Connect
4. Returns the secret to the caller

### Flow

```
1. Client requests: GET /v1/vaults/{vault}/items/{item}
2. op-gate checks policy (auto-approve vs require approval)
3. If approval required:
   a. op-gate calls privacyIDEA /validate/triggerchallenge
   b. privacyIDEA sends push to phone
   c. User approves on phone (with biometric)
   d. op-gate polls /validate/check for success
4. On approval (or auto-approve), op-gate proxies to Connect
5. Connect returns secret data
6. op-gate returns response to client
```

### Configuration

```nix
services.op-gate = {
  enable = mkEnableOption "1Password approval gate service";
  
  port = mkOption {
    type = types.port;
    default = 8081;
    description = "Port for op-gate API";
  };
  
  listenAddress = mkOption {
    type = types.str;
    default = "127.0.0.1";
    description = "Address to bind op-gate";
  };
  
  privacyidea = {
    url = mkOption {
      type = types.str;
      default = "http://127.0.0.1:5000";
    };
    
    realm = mkOption {
      type = types.str;
      default = "op";
    };
  };
  
  connect = {
    url = mkOption {
      type = types.str;
      default = "http://127.0.0.1:8080";
      description = "1Password Connect API URL";
    };
    
    tokenFile = mkOption {
      type = types.path;
      description = "Path to Connect access token";
    };
  };
  
  # Vault patterns that skip approval
  autoApproveVaults = mkOption {
    type = types.listOf types.str;
    default = [];
    example = [ "Development" "Personal" ];
  };
  
  # Items that always require approval
  alwaysRequireItems = mkOption {
    type = types.listOf types.str;
    default = [ "Production/*" "Infrastructure/*" ];
  };
  
  timeout = mkOption {
    type = types.int;
    default = 300;
    description = "Approval timeout in seconds";
  };
};
```

### op-gate API

op-gate exposes a subset of the 1Password Connect API:

| Endpoint | Description |
|----------|-------------|
| `GET /v1/vaults` | List accessible vaults |
| `GET /v1/vaults/{id}/items` | List items in vault |
| `GET /v1/vaults/{id}/items/{id}` | Get item (triggers approval) |
| `GET /health` | Health check |
| `GET /heartbeat` | Heartbeat for monitoring |

### Client Usage

Clients can use op-gate directly or via environment variable:

```bash
# Direct API call
curl -H "Authorization: Bearer $OP_GATE_TOKEN" \
  http://localhost:8081/v1/vaults/prod/items/db-password

# Or configure op CLI to use op-gate as Connect server
export OP_CONNECT_HOST=http://localhost:8081
export OP_CONNECT_TOKEN=$OP_GATE_TOKEN
op read op://prod/db-password/password
```

### Integration with AI Agents

AI agents use op-gate the same way as interactive users:

```python
# Example: OpenCode accessing a secret
import requests

response = requests.get(
    "http://localhost:8081/v1/vaults/Infrastructure/items/api-key",
    headers={"Authorization": f"Bearer {token}"}
)
# Push notification sent to user's phone
# User approves with biometric
# Response contains the secret
secret = response.json()["fields"][0]["value"]
```
```

## Mobile App: pi-authenticator Fork

### Repository

Fork `privacyidea/pi-authenticator` to add biometric-gated signing.

### Required Modifications

1. **Biometric Gate**: Before signing approval response, require Face ID/fingerprint
2. **Key Storage**: Store signing key in secure enclave, require biometric to access
3. **UI Enhancement**: Show full command context in approval dialog
4. **Tailscale Integration**: Configure server URL via Tailscale hostname

### Biometric Implementation

```dart
// Pseudocode for biometric-gated signing
Future<void> approveChallenge(Challenge challenge) async {
  // 1. Require biometric authentication
  final authenticated = await LocalAuthentication.authenticate(
    localizedReason: 'Approve: ${challenge.context}',
    biometricOnly: true,
  );
  
  if (!authenticated) {
    throw BiometricFailedException();
  }
  
  // 2. Only after biometric success, sign the challenge
  final signature = await secureEnclave.sign(
    challenge.nonce,
    requireBiometric: true,  // Key requires biometric to use
  );
  
  // 3. Send signed response to server
  await sendApproval(challenge.id, signature);
}
```

### Build Targets

- iOS: App Store or TestFlight
- Android: APK sideload or Play Store

## Nix Role Definition

### Role: `approval`

Add to `bundles.nix`:

```nix
approval = {
  packages = with pkgs; [
    privacyidea            # MFA Server
    pam_privacyidea        # PAM module
    onepassword-connect    # 1Password Connect server
    op-gate                # Approval gate service
  ];
  
  # Home-manager configuration
  homeModules = [
    ./modules/home-manager/approval
  ];
  
  # System configuration (for PAM and services)
  nixosModules = [
    ./modules/nixos/approval
  ];
  
  darwinModules = [
    ./modules/darwin/approval
  ];
};
```

### Dependencies

- Requires `tailscale` role (for mobile app connectivity)
- Requires `llm-client` or `developer` role (typical users)
- Works with `base` role

## Implementation Phases

### Phase 1: Server Setup

1. Package privacyIDEA for Nix (if not already available)
2. Create NixOS/nix-darwin module for privacyIDEA
3. Configure local SQLite database
4. Set up initial admin user and realm
5. Create push token enrollment flow

**Deliverables**:
- `modules/common/privacyidea.nix` - Shared configuration
- `modules/nixos/privacyidea.nix` - NixOS service
- `modules/darwin/privacyidea.nix` - macOS service (launchd)

### Phase 2: PAM Integration

1. Package pam_privacyidea for Nix (Linux)
2. **Fork and port pam_privacyidea for macOS** (see Decision D1)
3. Configure PAM for sudo on both platforms
4. Test sudo approval flow with stock pi-authenticator
5. Add event handler for command context in push

**Deliverables**:
- `modules/nixos/pam-privacyidea.nix` - Linux PAM configuration
- `modules/darwin/pam-privacyidea.nix` - macOS PAM configuration
- `packages/pam-privacyidea-darwin/` - Ported macOS PAM module (fork of upstream)

### Phase 3: Mobile App Fork

1. Fork pi-authenticator repository
2. Add biometric requirement before signing
3. Store signing key in secure enclave
4. Enhance UI to show command context
5. Build and distribute app

**Deliverables**:
- Forked repository: `funkymonkeymonk/pi-authenticator`
- iOS build (TestFlight)
- Android build (APK)

### Phase 4: 1Password Connect Integration

1. Package 1Password Connect for NixOS (Docker or native)
2. Create NixOS module for Connect server
3. Create `op-gate` service that wraps Connect with privacyIDEA approval
4. Implement policy engine for auto-approve patterns
5. Test with AI agent workflows
6. Document usage

**Deliverables**:
- `modules/nixos/onepassword-connect.nix` - Connect server module
- `packages/op-gate/` - Approval gate service
- `modules/nixos/op-gate.nix` - op-gate service module

### Phase 5: Polish & Documentation

1. Create unified `approval` role in bundles.nix
2. Write user documentation
3. Add to machine configurations
4. Test end-to-end with AI agents

**Deliverables**:
- Updated `bundles.nix`
- `docs/how-to/setup-approval-system.md`
- `docs/reference/approval-role.md`

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Malware on workstation | Phone approval is out-of-band |
| Stolen phone | Biometric required for approval |
| Network MITM | Tailscale encryption, signed challenges |
| Replay attacks | Nonce in each challenge, short TTL |
| Brute force | Rate limiting in privacyIDEA |

### Key Security Properties

1. **Out-of-band verification**: Approval happens on separate device
2. **Cryptographic binding**: Challenge-response with asymmetric keys
3. **Biometric proof**: Approval requires physical presence
4. **Audit trail**: All operations logged
5. **No public exposure**: Server only accessible via Tailscale

## Decisions

### D1: macOS PAM Compatibility (resolved from Q1)

**Decision**: privacyidea-pam does NOT work on macOS out of the box. A **custom PAM module** must be developed for macOS.

**Research Findings**:

1. **privacyidea-pam is Linux-only**: The official module (`privacyidea/privacyidea-pam`) explicitly targets "Linux PAM stack" and uses Linux-specific paths (`/lib/security/`, `/lib64/security/`). The Makefile has no macOS support.

2. **macOS uses OpenPAM (BSD-based)**: Different from Linux-PAM. Key differences:
   - Modules located in `/usr/lib/pam/` with `.so.2` extension
   - Different library dependencies (`libpam0g-dev` vs macOS system PAM)
   - Configuration in `/etc/pam.d/` (similar structure, different modules)

3. **macOS PAM customization is supported**: Apple provides `sudo_local` as an include point for custom modules that survives system updates. Native `pam_tid.so.2` (Touch ID) demonstrates custom auth modules work.

4. **No existing macOS issues/PRs**: GitHub search shows zero macOS-related discussions in privacyidea-pam repository.

**Implementation Approach for macOS**:

| Option | Effort | Risk | Recommendation |
|--------|--------|------|----------------|
| Fork and port privacyidea-pam | Medium | Medium | **Recommended** |
| Write new PAM module from scratch | High | Low | Fallback option |
| Use wrapper script instead of PAM | Low | High | Not recommended |

**Recommended approach**: Fork `privacyidea/privacyidea-pam` and port to macOS by:
1. Updating Makefile for Darwin target detection (`uname -s`)
2. Adjusting library paths (`/usr/lib/pam/`)  
3. Linking against macOS PAM headers (available in Xcode CLT)
4. Testing with `/etc/pam.d/sudo_local`

**Module location on macOS**:
```
/usr/lib/pam/pam_privacyidea.so.2
```

**PAM configuration via sudo_local**:
```
# /etc/pam.d/sudo_local
auth       sufficient     pam_privacyidea.so.2 url=http://127.0.0.1:5000 realm=local pollTime=120
```

### D2: 1Password Connect as Backend (resolved from Q1)

**Decision**: Use **1Password Connect** as the secrets backend instead of wrapping the `op` CLI. op-gate becomes a service that gates Connect API access with privacyIDEA approval.

**Research Findings**:

1. **op CLI limitations for this use case**:
   - Shell wrapper approach is fragile (parsing CLI output)
   - Process spawning overhead for each request
   - Complex session management (biometric, desktop app integration)
   - Biometric prompts can't be triggered by AI agents

2. **1Password Connect advantages**:

   | Aspect | op CLI Wrapper | 1Password Connect |
   |--------|----------------|-------------------|
   | Architecture | Shell wrapper, forks process | REST API, proper service |
   | Performance | Process spawn per request | Persistent connection, cached |
   | Error handling | Parse CLI output | Structured JSON responses |
   | Session management | Complex (biometric, sessions) | Token-based, stateless |
   | AI agent support | Requires workarounds | Native API access |
   | Auditability | Limited | Full API access logs |

3. **Connect architecture**:
   - Self-hosted Docker containers or systemd services
   - `connect-api`: REST API server
   - `connect-sync`: Syncs vault data from 1Password.com
   - Token-based authentication (ES256 signed JWTs)

4. **AI Agent Authentication**:
   - Both interactive users and AI agents use the same op-gate API
   - All requests trigger privacyIDEA push approval (unless auto-approved)
   - No special "service account" mode needed - op-gate handles approval uniformly

**Implementation Strategy**:

| User Type | Authentication Method | Flow |
|-----------|----------------------|------|
| Interactive user | op-gate API → privacyIDEA push → Connect | Phone approval required |
| AI agent | op-gate API → privacyIDEA push → Connect | Same flow, agent identified in push |

**Rationale**:
- **Proper service architecture**: REST API instead of shell wrapper
- **Better performance**: No process spawning, persistent connections
- **Cleaner integration**: Structured JSON responses, proper error handling
- **Uniform access**: Same approval flow for interactive users and AI agents
- **Native audit logging**: Connect provides API access logs
- **Simpler session management**: Token-based, no desktop app dependency

### D3: Session Approvals for Reduced Friction (resolved from Q1)

**Decision**: **Yes**, implement session approvals using privacyIDEA's built-in `auth_cache` feature. Support time-limited sessions scoped to **command type** (e.g., "approve sudo for 5 minutes") rather than global sessions.

**Research Findings**:

1. **privacyIDEA natively supports session approvals** via the `auth_cache` authentication policy:
   - Caches credentials for a configurable duration (e.g., "5m", "4h", "2d")
   - Supports frequency limits: `"4h/5m"` = cache for 4 hours, but require re-auth if more than 5 minutes between uses
   - Supports count limits: `"2m/3"` = cache for 2 minutes, max 3 authentications
   - Cache entries are per-user and can be scoped via policies

2. **Industry comparison**:
   - **Duo**: Uses "Remembered Devices" with configurable trust periods (typically hours/days)
   - **Okta**: Device trust caching with session timeouts
   - Both use longer durations (hours) for device trust, shorter for sensitive operations

3. **Security implications**:
   - Short sessions (2-5 minutes) maintain security while reducing friction for burst operations
   - Per-command-type scoping limits blast radius (approving sudo doesn't approve op access)
   - Sessions should NOT persist across terminal restarts

4. **Session scope options evaluated**:

   | Scope | Security | UX | Complexity | Recommendation |
   |-------|----------|-----|------------|----------------|
   | Global ("approve everything") | Low | Best | Low | **Not recommended** |
   | Per-command-type (sudo, op) | Medium | Good | Low | **Recommended** |
   | Per-terminal | High | Good | Medium | Optional enhancement |
   | Per-specific-command | Highest | Poor | High | Overkill |

**Implementation**:

Use privacyIDEA's `auth_cache` policy with command-type-specific realms:

```python
# privacyIDEA policy for sudo session caching
{
    "scope": "authentication",
    "action": "auth_cache=5m",  # Cache for 5 minutes
    "realm": "sudo",
    "conditions": {
        "client_ip": "127.0.0.1"  # Only local requests
    }
}

# privacyIDEA policy for op-gate session caching
{
    "scope": "authentication", 
    "action": "auth_cache=2m/3",  # 2 minutes, max 3 uses
    "realm": "op",
    "conditions": {
        "client_ip": "127.0.0.1"
    }
}
```

**Configuration additions for NixOS module**:

```nix
services.privacyidea = {
  # ... existing options ...
  
  sessionCache = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable session caching to reduce approval friction";
    };
    
    sudo = {
      duration = mkOption {
        type = types.str;
        default = "5m";
        description = "Duration to cache sudo approvals (e.g., '5m', '2m/3')";
      };
    };
    
    op = {
      duration = mkOption {
        type = types.str;
        default = "2m";
        description = "Duration to cache 1Password CLI approvals";
      };
      
      maxUses = mkOption {
        type = types.nullOr types.int;
        default = 5;
        description = "Maximum cached authentications (null for unlimited)";
      };
    };
  };
};
```

**Configuration additions for op-gate**:

```nix
programs.op-gate = {
  # ... existing options ...
  
  sessionCache = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable session caching for reduced friction";
    };
    
    duration = mkOption {
      type = types.str;
      default = "2m";
      description = "Session duration (privacyIDEA auth_cache format)";
    };
    
    maxOperations = mkOption {
      type = types.nullOr types.int;
      default = 5;
      description = "Max operations per session (null for time-based only)";
    };
  };
};
```

**Rationale**:
- **Native support**: privacyIDEA's `auth_cache` is production-ready, no custom implementation needed
- **Per-command-type scoping**: Limits security exposure while providing meaningful UX improvement
- **Configurable**: Admins can tune duration/limits per their security requirements
- **Short defaults**: 2-5 minute defaults balance security and convenience for typical workflows
- **Count limits**: Prevents abuse even within time window (e.g., runaway scripts)
- **Defense in depth**: Session cache only applies locally (127.0.0.1), maintains out-of-band phone approval for initial auth

### D4: Agent Identification in Push Notifications (resolved from Q1)

**Decision**: Use **process ancestry detection** to identify the requesting agent. The PAM module and op-gate will detect parent process names (e.g., "opencode", "claude") and pass this information to privacyIDEA via the `client` parameter, which is then displayed in push notifications using the `push_text_on_mobile` policy.

**Research Findings**:

1. **privacyIDEA supports custom push text**: The `push_text_on_mobile` authentication policy allows customizing push notification content with template tags like `{user}`, `{serial}`, `{client_ip}`, and arbitrary attributes passed during authentication.

2. **Process ancestry is detectable on both platforms**:
   - **Linux**: `ps -o ppid= -p $$ && ps -p $(ppid) -o comm=`
   - **macOS**: Same commands work (BSD-derived ps)
   - Can traverse multiple levels to find known agent names

3. **privacyIDEA API accepts custom data**: The `/validate/check` and `/validate/triggerchallenge` endpoints accept additional parameters that can be used in event handlers and policies. The `client` parameter is specifically designed for client identification.

4. **Known AI agent process names**:
   - OpenCode: `opencode`
   - Claude Code: `claude`
   - Aider: `aider`
   - Generic shell: `zsh`, `bash`, etc.

**Implementation Approach**:

| Component | Detection Method | Data Flow |
|-----------|------------------|-----------|
| PAM module | Detect grandparent process of sudo | Pass as `client` param to privacyIDEA |
| op-gate | Detect parent process | Pass as `client` param to privacyIDEA |
| privacyIDEA | Policy template | Display in push notification |

**Process Detection Logic** (for PAM module and op-gate):

```python
# Pseudocode for agent detection
KNOWN_AGENTS = {
    "opencode": "OpenCode",
    "claude": "Claude Code", 
    "aider": "Aider",
}

def detect_requesting_agent():
    """Walk process ancestry to find known AI agent."""
    pid = os.getppid()
    for _ in range(5):  # Check up to 5 ancestors
        if pid <= 1:
            break
        try:
            # Get process name
            with open(f"/proc/{pid}/comm", "r") as f:  # Linux
                name = f.read().strip()
            # macOS: use subprocess with ps -p {pid} -o comm=
        except:
            break
        
        # Check if this is a known agent
        for agent_key, agent_name in KNOWN_AGENTS.items():
            if agent_key in name.lower():
                return agent_name
        
        # Move to parent
        pid = get_parent_pid(pid)
    
    return "Terminal"  # Fallback for interactive use
```

**privacyIDEA Policy Configuration**:

```python
# Policy: push_text_on_mobile with agent context
{
    "scope": "authentication",
    "action": "push_text_on_mobile={client} requests: {user}@{realm}",
    "realm": "*"
}
```

**Example Push Notifications**:

| Scenario | Push Text |
|----------|-----------|
| OpenCode running sudo | "OpenCode requests: wweaver@local" |
| Claude Code accessing 1Password | "Claude Code requests: wweaver@op" |
| Interactive terminal sudo | "Terminal requests: wweaver@local" |
| Unknown caller | "Unknown requests: wweaver@local" |

**Configuration Additions for op-gate**:

```nix
programs.op-gate = {
  # ... existing options ...
  
  agentDetection = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Detect and report requesting agent in push notifications";
    };
    
    knownAgents = mkOption {
      type = types.attrsOf types.str;
      default = {
        "opencode" = "OpenCode";
        "claude" = "Claude Code";
        "aider" = "Aider";
      };
      description = "Map of process name patterns to display names";
    };
    
    ancestorDepth = mkOption {
      type = types.int;
      default = 5;
      description = "How many parent processes to check for agent detection";
    };
    
    fallbackName = mkOption {
      type = types.str;
      default = "Terminal";
      description = "Display name when no known agent is detected";
    };
  };
};
```

**PAM Module Modifications**:

The forked `pam_privacyidea` for macOS (and potentially upstream contribution for Linux) needs to:

1. Add agent detection before calling privacyIDEA API
2. Pass detected agent name in the `client` HTTP header or parameter
3. Include the command being executed (e.g., the sudo command line) in the request

```c
// Example addition to pam_privacyidea.c (conceptual)
char* detect_agent(pid_t pid) {
    // Walk process tree looking for known agents
    for (int i = 0; i < MAX_DEPTH; i++) {
        char* name = get_process_name(pid);
        if (is_known_agent(name)) {
            return get_agent_display_name(name);
        }
        pid = get_parent_pid(pid);
        if (pid <= 1) break;
    }
    return "Terminal";
}
```

**Security Considerations**:

| Concern | Mitigation |
|---------|------------|
| Agent spoofing (fake process name) | Detection is informational only; doesn't affect auth security |
| Performance overhead | Process tree walk is O(n) with small n (~5), negligible |
| Missing agent context | Fallback to "Terminal" or "Unknown" - still secure |

**Rationale**:
- **Feasible**: Process ancestry detection works reliably on both Linux and macOS
- **Extensible**: New agents can be added via configuration without code changes
- **Non-intrusive**: Agent detection is informational; failure doesn't block authentication
- **User-friendly**: Clear identification helps users make informed approval decisions
- **Security-neutral**: Agent name is context only; the actual security comes from push approval

### D5: Offline Fallback When Phone is Unreachable (resolved from Q1)

**Decision**: Implement a **tiered fallback strategy** using privacyIDEA's native token types: (1) pre-generated backup codes (Paper Token), (2) TOTP authenticator app as secondary device, and (3) time-limited bypass mode requiring physical presence. No automatic fallback to password-only authentication.

**Research Findings**:

1. **Industry standard approaches**:
   - **Duo**: Uses "bypass codes" (one-time use), hardware tokens as backup, and admin-settable "bypass status"
   - **Okta**: Pre-generated recovery codes, secondary enrolled devices, admin bypass
   - **Google**: Backup codes (8 single-use codes), secondary devices, security keys

2. **privacyIDEA native capabilities**:
   - **Paper Token (PPR)**: HOTP-based list of pre-generated OTP values that can be printed/stored securely
   - **TOTP Token**: Standard authenticator app (any TOTP app works, not just pi-authenticator)
   - **passthru policy**: Can fall back to LDAP/AD password (NOT recommended for this use case)
   - **passOnNoToken**: Auto-pass without token (dangerous, NOT recommended)

3. **Threat model considerations**:
   - Fallback must NOT be easier to compromise than push approval
   - Stolen laptop + backup codes = compromised (if codes stored on laptop)
   - Single-use codes are safer than multi-use
   - Time-limited bypass must require out-of-band verification

**Tiered Fallback Strategy**:

| Tier | Method | Security | Use Case |
|------|--------|----------|----------|
| 1 | Backup Codes (Paper Token) | High | Phone dead/lost, stored in physical safe |
| 2 | Secondary TOTP Device | High | Phone offline but have tablet/second phone |
| 3 | Time-Limited Bypass | Medium | Emergency, requires admin verification |
| 4 | Hardware Token (HOTP/TOTP) | Highest | YubiKey or similar for high-security users |

**Implementation Details**:

**Tier 1: Backup Codes (Paper Token)**

privacyIDEA's Paper Token generates a list of HOTP codes during enrollment. These should be:
- Printed and stored in a physical safe (NOT on the computer)
- Generated with 10-20 codes initially
- Each code is single-use
- User can request new codes when supply runs low

```nix
services.privacyidea = {
  # ... existing options ...
  
  fallback = {
    backupCodes = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable paper token backup codes";
      };
      
      count = mkOption {
        type = types.int;
        default = 10;
        description = "Number of backup codes to generate";
      };
      
      otpLength = mkOption {
        type = types.int;
        default = 8;
        description = "Length of backup OTP codes";
      };
    };
  };
};
```

**Tier 2: Secondary TOTP Device**

Users should be encouraged to enroll a secondary TOTP token on a different device (tablet, old phone, partner's phone). This provides:
- Full out-of-band verification
- No dependency on push notifications or Tailscale
- Works offline on the secondary device

```nix
services.privacyidea = {
  # ... existing options ...
  
  fallback = {
    # ... backup codes ...
    
    secondaryTotp = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Allow enrollment of secondary TOTP token";
      };
      
      requireDifferentDevice = mkOption {
        type = types.bool;
        default = true;
        description = "Warn if enrolling on same device as primary";
      };
    };
  };
};
```

**Tier 3: Time-Limited Bypass**

For emergencies when all other options fail. Requires:
- Out-of-band verification (phone call, video call, etc.)
- Creates audit log entry with reason
- Strictly time-limited (1 hour default, max 24 hours)
- Automatically reverts to normal after expiry

```nix
services.privacyidea = {
  # ... existing options ...
  
  fallback = {
    # ... other options ...
    
    emergencyBypass = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Allow time-limited emergency bypass";
      };
      
      defaultDuration = mkOption {
        type = types.str;
        default = "1h";
        description = "Default bypass duration";
      };
      
      maxDuration = mkOption {
        type = types.str;
        default = "24h";
        description = "Maximum bypass duration";
      };
      
      requireReason = mkOption {
        type = types.bool;
        default = true;
        description = "Require reason for bypass in audit log";
      };
    };
  };
};
```

**Tier 4: Hardware Token (Optional)**

For high-security environments or users who want maximum protection:

```nix
services.privacyidea = {
  fallback = {
    hardwareToken = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable hardware token enrollment";
      };
      
      allowedTypes = mkOption {
        type = types.listOf types.str;
        default = [ "hotp" "totp" ];
        description = "Allowed hardware token types";
      };
    };
  };
};
```

**op-gate Fallback Configuration**:

```nix
programs.op-gate = {
  # ... existing options ...
  
  fallback = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable fallback authentication methods";
    };
    
    allowBackupCodes = mkOption {
      type = types.bool;
      default = true;
      description = "Allow backup codes for op-gate auth";
    };
    
    allowSecondaryTotp = mkOption {
      type = types.bool;
      default = true;
      description = "Allow secondary TOTP for op-gate auth";
    };
    
    # NOTE: Emergency bypass for 1Password access should be 
    # more restricted than sudo bypass
    allowEmergencyBypass = mkOption {
      type = types.bool;
      default = false;
      description = "Allow emergency bypass for 1Password access (not recommended)";
    };
  };
};
```

**User Experience Flow**:

```
Phone unreachable during sudo/op access
         │
         ▼
┌─────────────────────────────────────┐
│ Push notification failed.           │
│                                     │
│ Fallback options:                   │
│ [1] Enter backup code               │
│ [2] Use secondary authenticator     │
│ [3] Request emergency bypass        │
│                                     │
│ Selection: _                        │
└─────────────────────────────────────┘
```

**Security Considerations**:

| Concern | Mitigation |
|---------|------------|
| Backup codes stolen with laptop | Store physically separate (safe, wallet) |
| Secondary device also offline | Hardware token provides final fallback |
| Bypass mode abuse | Time-limited, requires reason, audit logged |
| Social engineering for bypass | Out-of-band verification required |
| Running out of backup codes | UI warns when < 3 codes remain |

**Recovery Procedure**:

1. **Phone dead/lost**: Use backup codes, order replacement phone
2. **Phone offline (temporary)**: Use secondary TOTP or wait for connectivity
3. **All devices lost**: Request emergency bypass via out-of-band verification, re-enroll devices
4. **Tailscale down**: Secondary TOTP works without Tailscale (local TOTP validation)

**What We Explicitly Do NOT Support**:

- **Password-only fallback**: The `passthru` and `passOnNoToken` policies are NOT configured. Falling back to password-only defeats the purpose of the approval system.
- **Unlimited bypass**: Bypass must be time-limited and audited.
- **Backup codes on local disk**: Codes should be printed/stored physically offline.

**Rationale**:
- **Defense in depth**: Multiple fallback tiers ensure users aren't locked out while maintaining security
- **Native privacyIDEA support**: All fallback methods use built-in token types (no custom development)
- **Physical separation**: Backup codes stored offline prevent laptop theft from compromising everything
- **Audit trail**: All fallback uses are logged for security review
- **No security downgrade**: Every fallback method still requires proof of something the user has/knows beyond just the workstation password
- **Industry aligned**: Mirrors approaches used by Duo, Okta, and Google

## References

- [privacyIDEA Documentation](https://privacyidea.readthedocs.io/)
- [privacyIDEA Push Token](https://privacyidea.readthedocs.io/en/latest/tokens/tokentypes/push.html)
- [pi-authenticator Repository](https://github.com/privacyidea/pi-authenticator)
- [pam_privacyidea](https://github.com/privacyidea/pam_privacyidea)
- [Push Token Concept](https://github.com/privacyidea/privacyidea/wiki/concept%3A-PushToken)
- [Push Token Polling](https://github.com/privacyidea/privacyidea/wiki/concept%3A-pushtoken-poll)
- [1Password Connect Documentation](https://developer.1password.com/docs/connect/)
- [1Password Connect API Reference](https://developer.1password.com/docs/connect/connect-api-reference/)
