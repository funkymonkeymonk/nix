# OpenClaw MicroVM Security Enhancement Plans

## Implementation Roadmap

### 1. Network Egress Control (HIGH PRIORITY)

**Goal**: Restrict outbound connections to only approved destinations (Matrix server and Zen API).

**Current State**: Firewall allows all outbound connections.
**Target State**: Default-deny egress with explicit allowlist.

#### Implementation Steps

**Phase 1: Basic Egress Filtering (Week 1)**
1. Create `modules/nixos/egress-control.nix` module
   - Define allowed destinations configuration option
   - Generate nftables/iptables rules from configuration
   - Set default policy to DROP for forwarded traffic

2. Modify `targets/microvms/openclaw.nix`:
   ```nix
   services.egress-control = {
     enable = true;
     defaultPolicy = "deny";
     allowedDestinations = [
       { host = "matrix"; port = 8008; protocol = "tcp"; }
       { host = "api.opencode.ai"; port = 443; protocol = "tcp"; }
     ];
   };
   ```

3. Add DNS resolution handling:
   - Cache DNS lookups for configured hosts
   - Update firewall rules when IPs change
   - Log blocked connection attempts

**Phase 2: Approval Workflow (Week 2-3)**
1. Create `openclaw-egress-monitor` service:
   - Monitor blocked connection attempts via nftables logs
   - Expose API endpoint for pending approvals
   - Store approved destinations persistently

2. Create CLI tool `openclaw-approve-egress`:
   ```bash
   # List pending requests
   openclaw-approve-egress list
   
   # Approve a destination
   openclaw-approve-egress allow --host api.example.com --port 443 --reason "Needed for skill X"
   
   # View audit log
   openclaw-approve-egress log
   ```

3. Add notification integration:
   - Send notifications to Matrix when egress blocked
   - Include context about what the agent was doing

**Phase 3: Policy Engine (Week 4)**
1. Implement policy rules:
   - Auto-approve known-good destinations (GitHub, npm registry)
   - Rate limiting per destination
   - Time-based restrictions (e.g., no external calls after hours)

2. Add policy hot-reload:
   - Watch `/etc/openclaw/egress-policy.json`
   - Apply changes without restart

**Estimated Effort**: 3-4 weeks
**Dependencies**: None
**Risk**: Low (non-breaking, can start with logging-only mode)

---

### 2. Seccomp Syscall Filtering (HIGH PRIORITY)

**Goal**: Restrict which system calls the OpenClaw process can make.

**Current State**: Only basic systemd hardening (NoNewPrivileges, ProtectSystem).
**Target State**: Whitelist-only syscall filtering with seccomp-bpf.

#### Implementation Steps

**Phase 1: Baseline Profile (Week 1)**
1. Install `strace` in microvm temporarily:
   ```nix
   environment.systemPackages = with pkgs; [ strace ];
   ```

2. Run OpenClaw with syscall tracing:
   ```bash
   strace -f -o /tmp/openclaw-syscalls.log -e trace=all \
     openclaw gateway --port 18789
   ```

3. Analyze syscall usage:
   ```bash
   # Extract unique syscalls
   grep -oP '^[0-9]+\s+\K[a-z_]+' /tmp/openclaw-syscalls.log | sort -u
   ```

4. Create baseline seccomp profile in JSON format.

**Phase 2: Seccomp Module (Week 2)**
1. Create `modules/nixos/seccomp.nix`:
   - Define syscall whitelist configuration
   - Generate seccomp-bpf bytecode
   - Integration with systemd

2. Modify OpenClaw service:
   ```nix
   SystemCallFilter = [
     # Allow standard Node.js syscalls
     "@system-service"
     "exit"
     "exit_group"
     "read"
     "write"
     "open"
     "openat"
     "close"
     "mmap"
     "munmap"
     "brk"
     "futex"
     "epoll_create1"
     "epoll_ctl"
     "epoll_pwait"
     "socket"
     "connect"
     "accept"
     "bind"
     "listen"
     "clone"
     "wait4"
     "getpid"
     "getppid"
     "getpgrp"
     "setpgid"
     "kill"
     "tgkill"
     "rt_sigaction"
     "rt_sigprocmask"
     "rt_sigreturn"
     "sigaltstack"
     "stat"
     "fstat"
     "lstat"
     "statx"
     "lseek"
     "ioctl"
     "fcntl"
     "access"
     "faccessat"
     "getcwd"
     "chdir"
     "fchdir"
     "rename"
     "renameat"
     "unlink"
     "unlinkat"
     "mkdir"
     "mkdirat"
     "rmdir"
     "link"
     "linkat"
     "symlink"
     "symlinkat"
     "readlink"
     "readlinkat"
     "chmod"
     "fchmod"
     "fchmodat"
     "chown"
     "fchown"
     "lchown"
     "fchownat"
     "pipe"
     "pipe2"
     "dup"
     "dup2"
     "dup3"
     "fcntl"
     "getdents64"
     "pread64"
     "pwrite64"
     "sendfile"
     "signalfd4"
     "eventfd2"
     "timerfd_create"
     "timerfd_settime"
     "timerfd_gettime"
     "prlimit64"
     "getrlimit"
     "setrlimit"
     "getrusage"
     "times"
     "gettimeofday"
     "clock_gettime"
     "clock_getres"
     "nanosleep"
     "sched_yield"
     "sched_getaffinity"
     "sched_setaffinity"
     "sched_getparam"
     "sched_getscheduler"
     "sched_setscheduler"
     "sched_get_priority_min"
     "sched_get_priority_max"
     "getuid"
     "geteuid"
     "getgid"
     "getegid"
     "getgroups"
     "setuid"
     "setgid"
     "setgroups"
     "setreuid"
     "setregid"
     "setresuid"
     "setresgid"
     "getresuid"
     "getresgid"
     "capget"
     "capset"
     "prctl"
     "arch_prctl"
     "set_tid_address"
     "set_robust_list"
     "get_robust_list"
     "fadvise64"
     "madvise"
     "mprotect"
     "mlock"
     "munlock"
     "mlockall"
     "munlockall"
     "mincore"
     "msync"
     "personality"
     "umask"
     "getrandom"
     "sysinfo"
     "uname"
     "getsockname"
     "getpeername"
     "getsockopt"
     "setsockopt"
     "shutdown"
     "sendto"
     "recvfrom"
     "sendmsg"
     "recvmsg"
     "socketpair"
     "getpmsg"
     "putpmsg"
     "poll"
     "ppoll"
     "select"
     "pselect6"
     "readv"
     "writev"
     "preadv"
     "pwritev"
     "getdents"
     "inotify_init"
     "inotify_init1"
     "inotify_add_watch"
     "inotify_rm_watch"
     "fanotify_init"
     "fanotify_mark"
   ];
   SystemCallErrorNumber = "EPERM";
   SystemCallArchitectures = "native";
   ```

**Phase 3: Dynamic Profile Updates (Week 3)**
1. Create syscall monitoring:
   - Log denied syscalls
   - Alert on unexpected syscall failures

2. Add profile validation:
   - Test in staging before production
   - Dry-run mode that warns but doesn't block

**Estimated Effort**: 2-3 weeks
**Dependencies**: None
**Risk**: Medium (could break OpenClaw if syscalls missing)
**Mitigation**: Extensive testing in dev-vm first

---

### 3. Privacy Router (MEDIUM PRIORITY)

**Goal**: Intercept and control inference API calls, routing sensitive data to local models.

**Current State**: OpenClaw connects directly to Zen API.
**Target State**: All inference goes through policy-controlled proxy.

#### Implementation Steps

**Phase 1: LiteLLM Proxy Setup (Week 1)**
1. Add LiteLLM proxy service:
   ```nix
   services.litellm-proxy = {
     enable = true;
     config = {
       model_list = [
         {
           model_name = "local-ollama";
           litellm_params = {
             model = "ollama/qwen3.5";
             api_base = "http://localhost:11434";
           };
         }
         {
           model_name = "zen-default";
           litellm_params = {
             model = "openai/zen-default";
             api_key = "os.environ/ZEN_API_KEY";
             api_base = "https://api.opencode.ai/v1";
           };
         }
       ];
       router_settings = {
         routing_strategy = "simple-shuffle";
       };
     };
   };
   ```

2. Configure OpenClaw to use proxy:
   ```nix
   services.openclaw.extraConfig = {
     agent.model = "local-ollama";  # Default to local
     gateway.proxy = {
       enabled = true;
       url = "http://localhost:4000";
     };
   };
   ```

**Phase 2: Policy Engine (Week 2-3)**
1. Create routing policies:
   - Route sensitive operations (code with credentials) to local models
   - Route general queries to cloud for better performance
   - PII detection before sending to cloud

2. Implement content filtering:
   ```python
   # In LiteLLM proxy callback
   def pre_call_hook(request):
       if contains_pii(request["messages"]):
           request["model"] = "local-ollama"
       return request
   ```

**Phase 3: User Approval Flow (Week 4)**
1. Create approval queue for cloud fallback:
   - When local model can't handle request
   - Queue for user approval via Matrix
   - Timeout and fallback options

2. Add audit logging:
   - Log all inference requests
   - Track which model was used and why
   - Export metrics

**Estimated Effort**: 3-4 weeks
**Dependencies**: Ollama setup (already exists)
**Risk**: Medium (adds latency, complexity)
**Benefit**: High (data privacy)

---

### 4. Filesystem Restrictions (MEDIUM PRIORITY)

**Goal**: Implement Landlock-like filesystem sandboxing.

**Current State**: OpenClaw can read/write anywhere in its home directory.
**Target State**: Whitelist-only filesystem access.

#### Implementation Steps

**Phase 1: Read-Only Root (Week 1)**
1. Enhance systemd service:
   ```nix
   # In openclaw service config
   ProtectSystem = "strict";  # Already done - make read-only
   ProtectHome = true;        # Already done
   
   # Add explicit bind mounts
   BindReadOnlyPaths = [
     "/nix/store"
     "/etc/openclaw"
     "/etc/ssl"           # For HTTPS
     "/etc/resolv.conf"   # For DNS
   ];
   BindPaths = [
     cfg.dataDir
     "/tmp"
   ];
   
   # Additional restrictions
   TemporaryFileSystem = "/:ro";
   RootDirectory = cfg.dataDir;  # Chroot-like behavior
   RootDirectoryStartOnly = true;
   ```

**Phase 2: Directory Whitelist (Week 2)**
1. Create directory structure:
   ```
   /home/dev/
   ├── .openclaw/          # Config (read-only after setup)
   ├── workspace/          # Working directory (read-write)
   ├── cache/              # Temporary cache (read-write, auto-cleaned)
   └── logs/               # Log files (append-only)
   ```

2. Implement using Linux mount namespaces:
   ```nix
   # Create wrapper script that sets up mounts
   ExecStartPre = pkgs.writeShellScript "openclaw-fs-setup" ''
     # Create overlay structure
     mkdir -p ${cfg.dataDir}/workspace
     mkdir -p ${cfg.dataDir}/cache
     mkdir -p ${cfg.dataDir}/logs
     
     # Set permissions
     chmod 755 ${cfg.dataDir}/workspace
     chmod 700 ${cfg.dataDir}/cache
     chmod 750 ${cfg.dataDir}/logs
   '';
   ```

**Phase 3: Audit and Enforcement (Week 3)**
1. Add filesystem audit:
   - Monitor file access with fanotify
   - Log attempts to access outside allowed paths
   - Alert on violations

2. Create audit dashboard:
   - View recent file operations
   - Approve/deny access requests
   - Review patterns

**Estimated Effort**: 2-3 weeks
**Dependencies**: None
**Risk**: Low-Medium (could break file operations)
**Testing**: Extensive testing with actual OpenClaw usage

---

### 5. Network Namespace Isolation (LOW PRIORITY)

**Goal**: Better network isolation than default microvm networking.

**Current State**: User-mode networking (SLIRP) with basic NAT.
**Target State**: Dedicated network namespace with custom routing.

#### Implementation Steps

**Phase 1: Bridge Network Setup (Week 1)**
1. Configure bridge on host:
   ```nix
   # On host (if not already configured)
   networking.bridges.br-microvm.interfaces = [];
   networking.interfaces.br-microvm.ipv4.addresses = [{
     address = "10.0.3.1";
     prefixLength = 24;
   }];
   ```

2. Update microvm networking:
   ```nix
   microvm.vms.openclaw = {
     networking = {
       type = "bridge";
       bridge = "br-microvm";
       interfaces = [{
         type = "macvtap";
         id = "openclaw0";
         mac = "02:00:00:00:00:02";
       }];
     };
   };
   ```

**Phase 2: Custom Routing (Week 2)**
1. Implement policy-based routing:
   ```nix
   networking.iproute2 = {
     enable = true;
     rttables = ''
       100 openclaw
     '';
   };
   
   # Route all traffic through egress controller
   networking.firewall.extraCommands = ''
     ip rule add fwmark 0x1 lookup 100
     ip route add default via 10.0.3.1 table 100
   '';
   ```

**Phase 3: Service Mesh Integration (Week 3-4)**
1. Add sidecar proxy:
   - Envoy or similar
   - Handle all outbound connections
   - Apply policies at proxy level

**Estimated Effort**: 3-4 weeks
**Dependencies**: Network egress control (for proxy)
**Risk**: Medium (networking changes can break connectivity)
**Benefit**: Medium (microvm already provides good isolation)

---

## Summary Timeline

| Feature | Priority | Effort | Timeline | Dependencies |
|---------|----------|--------|----------|--------------|
| Network Egress Control | HIGH | 3-4 weeks | Month 1 | None |
| Seccomp Syscall Filtering | HIGH | 2-3 weeks | Month 1 | None |
| Privacy Router | MEDIUM | 3-4 weeks | Month 2 | None |
| Filesystem Restrictions | MEDIUM | 2-3 weeks | Month 2 | None |
| Network Namespace Isolation | LOW | 3-4 weeks | Month 3 | Network Egress |

**Total Estimated Time**: 3-4 months for full implementation
**Recommended Phase 1** (highest ROI): Network Egress + Seccomp

---

## Repository Question: Should OpenClaw MicroVM Be In Its Own Repo?

### Arguments for Separate Repo

**Pros:**
1. **Isolation**: Security issues in OpenClaw don't affect main infrastructure
2. **Independent versioning**: Can release updates without rebuilding everything
3. **Specialized CI**: Custom security testing, penetration testing
4. **Community**: Could attract OpenClaw-specific contributors
5. **Simpler PRs**: Changes to OpenClaw don't require full flake rebuilds
6. **Secret management**: Could use different secrets backend
7. **Clear boundaries**: Forces clean interfaces between components

**Current Complexity Indicators:**
- 156 lines in microvm config
- 217 lines in service module
- Multiple documentation files
- Complex security requirements
- Service dependencies (Matrix, 1Password)

### Arguments Against Separate Repo (Keep in Main Repo)

**Pros:**
1. **Shared infrastructure**: Uses common modules (onepassword, options)
2. **Atomic changes**: Matrix + OpenClaw updates can be coordinated
3. **Consistency**: Same patterns, linting, CI as rest of project
4. **Easier maintenance**: One place to update shared modules
5. **Context**: Changes to shared code show impact on OpenClaw
6. **Flake simplicity**: No need for flake inputs to reference other repos
7. **Current size**: Not actually that complex yet (~400 lines total)

**Dependencies on Main Repo:**
- `modules/common/options.nix` - Shared configuration options
- `modules/common/onepassword.nix` - Secrets management
- `flake.nix` - MicroVM helper functions (`mkMicrovm`)
- `bundles.nix` - Package bundles
- `.github/workflows/` - CI infrastructure

### Recommendation: **Keep in Main Repo (for now)**

**Thresholds for when to split:**
- [ ] MicroVM exceeds 500 lines
- [ ] Service module exceeds 500 lines
- [ ] Need independent release cycle
- [ ] Multiple teams working on it
- [ ] Want to open-source just the OpenClaw deployment
- [ ] Need different CI/security requirements

**Current status**: 2/6 thresholds met (complexity ~400 lines)

**Suggested approach:**
1. **Keep in main repo** while implementing security enhancements
2. **Extract common patterns** into reusable modules first
3. **Re-evaluate after security phase 1** (3 months)
4. If it grows beyond 500 lines OR needs independent releases → split

**If you do split later:**
- Use flake input: `inputs.openclaw-microvm.url = "github:funkymonkeymonk/openclaw-nix"`
- Extract common modules to separate repo first
- Keep minimal interface between repos

---

## Next Steps

1. **Immediate** (this week):
   - Review and approve these plans
   - Create GitHub issues for each feature
   - Prioritize Network Egress Control as first implementation

2. **Short-term** (next 2 weeks):
   - Begin implementation of Network Egress Control
   - Document current security baseline
   - Set up monitoring for blocked connections

3. **Medium-term** (next 2 months):
   - Complete Phase 1 features (Egress + Seccomp)
   - Security audit of current implementation
   - Decide on repo split question

Would you like me to start implementing any of these features, or create detailed GitHub issues for tracking?
