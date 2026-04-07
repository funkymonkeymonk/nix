---
title: "Set Up OpenClaw MicroVM (Automated)"
description: "Deploy OpenClaw AI assistant in a MicroVM using cloud-init automation. Designed for LLM execution with verification at each step."
type: how-to
audience: agent
automation-ready: true
estimated-time: 10-15 minutes
last-reviewed: 2026-04-06
---

# Set Up OpenClaw MicroVM (Automated)

This guide shows you how to deploy OpenClaw AI assistant in a MicroVM using cloud-init for full automation. No manual interaction required.

<!-- LLM: BEGIN AUTOMATED SECTION -->
<!-- LLM: Prerequisites: NixOS host with MicroVM support -->
<!-- LLM: Prerequisites: Cloud-init yaml ready or will be generated -->
<!-- LLM: Prerequisites: OpenClaw API key available -->
<!-- LLM: Verification: Services running and accessible -->

## Quick Start

For experienced users, the complete setup in one command block:

```bash
# 1. Prerequisites check
[[ -f /etc/opnix/token ]] || echo "WARNING: No 1Password token found"
command -v cloud-init &>/dev/null || echo "WARNING: cloud-init not installed"

# 2. Generate cloud-init configuration
sudo mkdir -p /etc
sudo tee /etc/cloud-init.yaml << 'EOF'
#cloud-config
hostname: openclaw-vm
fqdn: openclaw-vm.local
preserve_hostname: true
timezone: America/New_York
locale: en_US.UTF-8

# SSH access (add your key)
ssh_authorized_keys:
  - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8

# Nix configuration
nix:
  target: type-server
  flake: github:funkymonkeymonk/nix
  branch: main
  impure: true
  roles:
    - openclaw

# MicroVM definition
microvms:
  - name: openclaw
    flake: .#microvm.nixosConfigurations.openclaw
    ipAddress: 192.168.83.16
    autoStart: true
EOF

# 3. Apply cloud-init configuration
sudo mkdir -p /var/lib/microvms/cloud-init
sudo cp /etc/cloud-init.yaml /var/lib/microvms/cloud-init/openclaw.yaml

# 4. Build and run the MicroVM
cd ~/nix 2>/dev/null || cd /root/nix 2>/dev/null || cd /tmp
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure &

# 5. Wait for VM to boot
sleep 10
echo "MicroVM starting... check with: ps aux | grep microvm"
```

<!-- LLM: END AUTOMATED SECTION -->

---

## Prerequisites

<!-- LLM: BEGIN VERIFICATION SECTION -->

### Required

1. **NixOS host with MicroVM support**
   ```bash
   # Verification command:
   [[ -d /nix/store ]] && echo "✓ NixOS detected" || echo "✗ Not NixOS"
   
   # Check KVM:
   lsmod | grep -q kvm && echo "✓ KVM enabled" || echo "✗ KVM not loaded"
   ```

2. **At least 4GB RAM available**
   ```bash
   # Verification:
   free -h | grep Mem | awk '{print $7}'  # Available memory
   ```

3. **OpenClaw API key**
   ```bash
   # Store in environment:
   export OPENCODE_API_KEY="your-key-here"
   
   # Or in file:
   echo "your-key-here" | sudo tee /etc/openclaw-api-key
   sudo chmod 600 /etc/openclaw-api-key
   ```

### Optional (Enhanced Features)

4. **1Password service account** (for secrets management)
   ```bash
   # Verification:
   [[ -f /etc/opnix/token ]] && echo "✓ 1Password configured" || echo "⚠ 1Password not configured (optional)"
   ```

5. **Matrix server** (for chat integration)
   ```bash
   # Verification:
   curl -s http://matrix:8008/_matrix/client/versions 2>/dev/null | grep -q versions && echo "✓ Matrix available" || echo "⚠ Matrix not available (optional)"
   ```

<!-- LLM: END VERIFICATION SECTION -->

---

## Step-by-Step Setup

### Step 1: Prepare the Host

<!-- LLM: Prerequisites: NixOS host -->
<!-- LLM: Verification: KVM enabled, git clone -->

```bash
# Clone the repository
mkdir -p ~/nix
cd ~/nix
git clone https://github.com/funkymonkeymonk/nix.git . 2>/dev/null || git pull

# Verify MicroVM host module is available
[[ -f modules/microvm/default.nix ]] && echo "✓ MicroVM module found" || echo "✗ MicroVM module missing"
```

**Expected output:**
```
✓ MicroVM module found
```

**Error handling:**
```bash
# If git clone fails:
# Check network: ping github.com
# Check git: which git || nix-shell -p git
# Alternative: Download zip from GitHub
```

### Step 2: Configure Cloud-Init

<!-- LLM: BEGIN AUTOMATED SECTION -->
<!-- LLM: This creates the automated configuration file -->
<!-- LLM: Verification: File created with valid content -->

Create the cloud-init configuration file:

```bash
# Set variables
VM_NAME="openclaw-vm"
VM_IP="192.168.83.16"
SSH_KEY="${SSH_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8}"
OPENCODE_KEY="${OPENCODE_API_KEY:-placeholder}"

# Create cloud-init file
sudo tee /etc/cloud-init.yaml << EOF
#cloud-config
# Generated for OpenClaw MicroVM
# Date: $(date -Iseconds)

hostname: ${VM_NAME}
fqdn: ${VM_NAME}.local
preserve_hostname: true
timezone: America/New_York
locale: en_US.UTF-8

# SSH authorized keys
ssh_authorized_keys:
  - ${SSH_KEY}

# Boot commands
bootcmd:
  - echo "Starting OpenClaw MicroVM..."
  - mkdir -p /run/openclaw

# Run commands on first boot
runcmd:
  - echo "OpenClaw VM initialized"

# Nix configuration
nix:
  target: type-server
  flake: github:funkymonkeymonk/nix
  branch: main
  impure: true
  roles:
    - openclaw
EOF

# Verify file created
[[ -f /etc/cloud-init.yaml ]] && echo "✓ Cloud-init config created" || echo "✗ Failed to create config"
cat /etc/cloud-init.yaml | head -5
```

**Expected output:**
```
✓ Cloud-init config created
#cloud-config
# Generated for OpenClaw MicroVM
# Date: 2026-04-06T...

hostname: openclaw-vm
```

**Verification:**
```bash
# Check file is valid YAML
python3 -c "import yaml; yaml.safe_load(open('/etc/cloud-init.yaml'))" && echo "✓ Valid YAML"
```

<!-- LLM: END AUTOMATED SECTION -->

### Step 3: Configure OpenClaw API Key

<!-- LLM: Prerequisites: API key available -->
<!-- LLM: Verification: Key stored securely -->

Choose one method:

**Option A: Environment Variable (Simplest)**
```bash
# Set the API key
export OPENCODE_API_KEY="your-openclaw-api-key-here"

# Persist for systemd services
sudo mkdir -p /etc/openclaw
echo "OPENCODE_API_KEY=${OPENCODE_API_KEY}" | sudo tee /etc/openclaw/env
sudo chmod 600 /etc/openclaw/env

echo "✓ API key configured"
```

**Option B: 1Password Integration (Recommended)**
```bash
# Store in 1Password first:
# op item create --category password --title "OpenClaw API Key" \
#   --vault Homelab password="your-key-here"

# Create service account token file
echo "ops_your_service_account_token" | sudo tee /etc/opnix/token
sudo chmod 600 /etc/opnix/token

echo "✓ 1Password configured"
```

**Verification:**
```bash
# Check key is set (don't print it)
[[ -n "${OPENCODE_API_KEY}" ]] && echo "✓ API key in environment" || echo "✗ API key not found"
[[ -f /etc/openclaw/env ]] && echo "✓ API key file exists" || echo "⚠ API key file not found"
```

### Step 4: Generate MicroVM Configuration

<!-- LLM: BEGIN AUTOMATED SECTION -->
<!-- LLM: This generates the Nix configuration from cloud-init -->
<!-- LLM: Verification: Nix file created -->

```bash
# Ensure cloud-init directory exists
sudo mkdir -p /var/lib/microvms/cloud-init
sudo cp /etc/cloud-init.yaml /var/lib/microvms/cloud-init/openclaw.yaml

# Generate microvm.nix from cloud-init
# (Note: This is a simplified version - full nix-cloud-init microvm generate does more)
sudo mkdir -p /etc/nixos

sudo tee /etc/nixos/openclaw-microvm.nix << 'NIXEOF'
{ config, lib, pkgs, ... }:
let
  cloudInitDir = "/var/lib/microvms/cloud-init";
in {
  microvm.vms.openclaw = {
    flake = "github:funkymonkeymonk/nix#microvm.nixosConfigurations.openclaw";
    interfaces = [{
      type = "tap";
      id = "microvm-openclaw";
      mac = "02:00:00:00:00:16";
    }];
    hypervisor = pkgs.cloud-hypervisor;
    writableStoreOverlay = "/nix/.rw-store";
    shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
      {
        tag = "cloud-init";
        source = cloudInitDir;
        mountPoint = "/etc/cloud-init";
        proto = "virtiofs";
      }
    ];
    autostart = true;
  };
}
NIXEOF

echo "✓ MicroVM configuration generated"
ls -la /etc/nixos/openclaw-microvm.nix
```

**Expected output:**
```
✓ MicroVM configuration generated
-rw-r--r-- 1 root root ... /etc/nixos/openclaw-microvm.nix
```

<!-- LLM: END AUTOMATED SECTION -->

### Step 5: Build and Start the MicroVM

<!-- LLM: Prerequisites: Configuration files created -->
<!-- LLM: Verification: VM boots successfully -->

```bash
cd ~/nix

# Build the MicroVM (may take 10-20 minutes first time)
echo "Building MicroVM (this may take a while)..."
nix build .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure 2>&1 | tail -20

# Check build succeeded
[[ -d result ]] && echo "✓ Build successful" || echo "✗ Build failed"

# Run the MicroVM in background
echo "Starting MicroVM..."
nohup nix run .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure > /tmp/openclaw-vm.log 2>&1 &
VM_PID=$!
echo "VM started with PID: $VM_PID"
echo $VM_PID > /tmp/openclaw-vm.pid

# Wait for boot
sleep 15
echo "Waiting for VM to boot..."
```

**Expected output:**
```
Building MicroVM (this may take a while)...
✓ Build successful
Starting MicroVM...
VM started with PID: 12345
Waiting for VM to boot...
```

**Verification:**
```bash
# Check VM is running
ps aux | grep microvm | grep -v grep && echo "✓ VM process running" || echo "✗ VM not running"

# Check log for boot messages
tail -30 /tmp/openclaw-vm.log | grep -E "(booting|started|listening)" && echo "✓ VM booting"
```

### Step 6: Verify MicroVM is Accessible

<!-- LLM: Prerequisites: VM started -->
<!-- LLM: Verification: Can connect to VM -->

```bash
# Check network interface
ip addr show | grep "192.168.83" && echo "✓ Host network configured" || echo "⚠ Checking network..."

# Try to ping the VM (may take a moment)
for i in {1..10}; do
  if ping -c 1 -W 2 192.168.83.16 &>/dev/null; then
    echo "✓ VM is pingable at 192.168.83.16"
    break
  fi
  echo "Attempt $i/10: Waiting for VM network..."
  sleep 3
done

# Try SSH connection
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@192.168.83.16 "echo '✓ SSH connection successful'" 2>/dev/null || echo "⚠ SSH not ready yet (normal during boot)"
```

**Expected output:**
```
✓ Host network configured
Attempt 1/10: Waiting for VM network...
Attempt 2/10: Waiting for VM network...
✓ VM is pingable at 192.168.83.16
✓ SSH connection successful
```

### Step 7: Verify OpenClaw Services

<!-- LLM: Prerequisites: VM accessible via SSH -->
<!-- LLM: Verification: OpenClaw services running -->

```bash
# SSH into VM and check services
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
echo "=== OpenClaw VM Status ==="

# Check if OpenClaw user exists
id dev &>/dev/null && echo "✓ User 'dev' exists" || echo "⚠ User 'dev' not found"

# Check OpenClaw service (if using systemd)
if systemctl is-active openclaw-gateway &>/dev/null 2>&1; then
  echo "✓ OpenClaw gateway running"
  systemctl status openclaw-gateway --no-pager | head -5
elif systemctl is-active openclaw-gateway &>/dev/null 2>&1; then
  echo "✓ OpenClaw gateway running"
  systemctl status openclaw-gateway --no-pager | head -5
else
  echo "⚠ Gateway service not found (may need manual start)"
fi

# Check environment
[[ -f /etc/openclaw/env ]] && echo "✓ Environment file exists" || echo "⚠ No environment file"

# Check port listening
ss -tlnp | grep -E "(18789|8080)" && echo "✓ Service listening on port" || echo "⚠ No service ports found"

echo ""
echo "=== VM Info ==="
hostname
uptime
ip addr show | grep inet | head -2
SSH_EOF
```

**Expected output:**
```
=== OpenClaw VM Status ===
✓ User 'dev' exists
✓ OpenClaw gateway running
● openclaw-gateway.service - OpenClaw Gateway
     Loaded: loaded (...)
     Active: active (running)
✓ Service listening on port

=== VM Info ===
openclaw-vm
 12:34:56 up 5 min,  0 users,  load average: 0.50, 0.30, 0.15
inet 192.168.83.16/24 ...
```

---

## Verification Summary

<!-- LLM: BEGIN VERIFICATION SECTION -->

Run this comprehensive check:

```bash
echo "=== OpenClaw MicroVM Verification ==="
echo ""

# 1. Host prerequisites
echo "1. Host Prerequisites:"
[[ -d /nix/store ]] && echo "   ✓ NixOS" || echo "   ✗ Not NixOS"
lsmod | grep -q kvm && echo "   ✓ KVM" || echo "   ✗ No KVM"
[[ -f /etc/cloud-init.yaml ]] && echo "   ✓ Cloud-init config" || echo "   ✗ No cloud-init"

# 2. VM process
echo ""
echo "2. VM Process:"
[[ -f /tmp/openclaw-vm.pid ]] && echo "   ✓ PID file exists" || echo "   ✗ No PID file"
ps aux | grep -q "microvm.*openclaw" && echo "   ✓ Process running" || echo "   ✗ Process not found"

# 3. Network
echo ""
echo "3. Network:"
ping -c 1 -W 2 192.168.83.16 &>/dev/null && echo "   ✓ VM pingable" || echo "   ✗ Not pingable"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@192.168.83.16 "echo 'ok'" &>/dev/null && echo "   ✓ SSH accessible" || echo "   ✗ SSH not ready"

# 4. Services
echo ""
echo "4. Services (inside VM):"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@192.168.83.16 "systemctl is-active openclaw-gateway openclaw-gateway 2>/dev/null | grep -q active && echo '   ✓ Gateway active' || echo '   ⚠ Check manually'" 2>/dev/null

echo ""
echo "=== End Verification ==="
```

**All checks should show ✓ for successful setup.**

<!-- LLM: END VERIFICATION SECTION -->

---

## Optional: Add Matrix Integration

<!-- LLM: Prerequisites: Matrix server running -->
<!-- LLM: Verification: OpenClaw connected to Matrix -->

If you have a Matrix server, connect OpenClaw to it:

```bash
# SSH into VM
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
# Check Matrix connectivity
curl -s http://192.168.83.15:8008/_matrix/client/versions 2>/dev/null | grep -q versions && echo "✓ Matrix reachable" || echo "✗ Matrix not reachable"

# Configure Matrix in OpenClaw (edit config file)
# The exact method depends on OpenClaw's configuration method
echo "Matrix integration requires:"
echo "  1. Matrix homeserver URL (http://192.168.83.15:8008)"
echo "  2. Bot user ID (@openclaw:matrix.local)"
echo "  3. Access token (from Matrix login)"
SSH_EOF
```

For full Matrix setup, see [Set up OpenClaw MicroVM](setup-openclaw-microvm.md).

---

## Optional: Add 1Password Secrets

<!-- LLM: Prerequisites: 1Password service account -->
<!-- LLM: Verification: Secrets syncing -->

For automatic secret management:

```bash
# SSH into VM
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
# Install and configure opnix
# Note: This requires the VM configuration to include opnix module

# Check if opnix is available
systemctl is-active onepassword-secrets &>/dev/null && echo "✓ Opnix running" || echo "⚠ Opnix not configured"

# Check secrets location
ls -la /run/secrets/ 2>/dev/null || echo "⚠ No secrets directory"
SSH_EOF
```

For full 1Password setup, see [Set up 1Password](setup-1password.md).

---

## Troubleshooting

### VM Fails to Start

**Symptom:** Build succeeds but VM doesn't run

```bash
# Check for errors in log
tail -50 /tmp/openclaw-vm.log

# Check if KVM is available
lsmod | grep kvm || echo "KVM not loaded - check BIOS settings"
sudo dmesg | grep -i kvm | tail -5

# Try running interactively (not in background)
cd ~/nix
nix run .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure
```

### Cannot SSH into VM

**Symptom:** VM running but SSH connection refused

```bash
# Check if VM is actually booted
ps aux | grep microvm | grep -v grep
tail -20 /tmp/openclaw-vm.log | grep -E "(boot|ssh|listen)"

# Try with verbose SSH
ssh -vvv -o StrictHostKeyChecking=no root@192.168.83.16

# Check network
echo "Host interfaces:"
ip addr show | grep inet
echo ""
echo "VM should be at: 192.168.83.16"

# VM may still be booting - wait and retry
sleep 30
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@192.168.83.16 "hostname"
```

### OpenClaw Service Not Running

**Symptom:** VM accessible but no OpenClaw service

```bash
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
# List all systemd services
systemctl list-units --type=service | grep -E "(open|openclaw|claw)"

# Check if openclaw is installed
which openclaw || echo "OpenClaw binary not found"
which openclaw || echo "OpenClaw binary not found"

# Check available packages
ls /nix/store | grep -i openclaw | head -5

# Manual start (if needed)
# Note: Exact command depends on OpenClaw's installation method
SSH_EOF
```

### API Key Not Found

**Symptom:** Service running but can't authenticate

```bash
# SSH into VM and check environment
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
# Check environment variables
env | grep -i openclaw || echo "No OPENCODE variables"

# Check environment file
[[ -f /etc/openclaw/env ]] && cat /etc/openclaw/env || echo "No env file"

# Check if API key is set
if [[ -f /etc/openclaw/env ]]; then
  source /etc/openclaw/env
  [[ -n "$OPENCODE_API_KEY" ]] && echo "API key configured" || echo "API key empty"
fi
SSH_EOF
```

### Cloud-Init Not Applied

**Symptom:** VM boots but cloud-init settings not applied

```bash
# Check cloud-init mounted correctly
ssh -o StrictHostKeyChecking=no root@192.168.83.16 << 'SSH_EOF'
mount | grep cloud-init
ls -la /etc/cloud-init/
cat /etc/cloud-init/*.yaml 2>/dev/null || echo "No cloud-init files"

# Check hostname
hostname
SSH_EOF

# If not mounted, check host configuration
ls -la /var/lib/microvms/cloud-init/
cat /etc/nixos/openclaw-microvm.nix | grep -A 5 cloud-init
```

---

## Maintenance

### Restart the MicroVM

```bash
# Stop current VM
if [[ -f /tmp/openclaw-vm.pid ]]; then
  kill $(cat /tmp/openclaw-vm.pid) 2>/dev/null
  sleep 5
fi

# Start again
cd ~/nix
nohup nix run .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure > /tmp/openclaw-vm.log 2>&1 &
echo $! > /tmp/openclaw-vm.pid

echo "VM restarted"
```

### Update the MicroVM

```bash
cd ~/nix
git pull

# Rebuild
nix build .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure

# Restart VM (see above)
```

### Clean Up

```bash
# Stop VM
kill $(cat /tmp/openclaw-vm.pid) 2>/dev/null

# Remove configuration
sudo rm -f /etc/cloud-init.yaml
sudo rm -f /etc/nixos/openclaw-microvm.nix
sudo rm -rf /var/lib/microvms/cloud-init/

# Remove logs
rm -f /tmp/openclaw-vm.log /tmp/openclaw-vm.pid

echo "Cleanup complete"
```

---

## Next Steps

After successful setup:

1. **Configure OpenClaw**: Edit configuration files inside the VM
2. **Set up monitoring**: Add health checks and alerts
3. **Add backup**: Back up configuration and data
4. **Scale up**: Run multiple MicroVMs for different tasks

### Related Documentation

- [Set up OpenClaw MicroVM](setup-openclaw-microvm.md) - Full setup with Matrix
- [Set up MicroVM Host](setup-microvm-host.md) - Host configuration
- [MicroVMs Reference](../reference/microvms.md) - Technical details
- [OpenClaw Documentation](https://docs.openclaw.ai) - OpenClaw usage

---

## Quick Reference

### Common Commands

```bash
# View VM logs
tail -f /tmp/openclaw-vm.log

# SSH into VM
ssh root@192.168.83.16

# Check VM status
ps aux | grep microvm | grep -v grep

# Restart VM
kill $(cat /tmp/openclaw-vm.pid)
# Then restart (see Step 5)

# Update configuration
# Edit /etc/cloud-init.yaml, then restart VM
```

### File Locations

| File | Path | Purpose |
|------|------|---------|
| Cloud-init config | `/etc/cloud-init.yaml` | VM initialization |
| Nix config | `/etc/nixos/openclaw-microvm.nix` | MicroVM definition |
| VM logs | `/tmp/openclaw-vm.log` | Boot and runtime logs |
| PID file | `/tmp/openclaw-vm.pid` | Process ID for management |
| API key | `/etc/openclaw/env` | Environment variables |

### Network Details

| Item | Value |
|------|-------|
| VM IP | `192.168.83.16` |
| Host IP | `192.168.83.1` |
| SSH | `root@192.168.83.16` |
| OpenClaw Port | `18789` (if configured) |

---

<!-- LLM: FINAL VERIFICATION CHECKLIST -->
<!-- LLM: All steps should show completion before finishing -->

**Setup Complete Checklist:**
- [ ] Cloud-init configuration created at `/etc/cloud-init.yaml`
- [ ] API key configured (environment or file)
- [ ] MicroVM configuration generated at `/etc/nixos/openclaw-microvm.nix`
- [ ] VM built successfully with `nix build`
- [ ] VM running (check with `ps aux | grep microvm`)
- [ ] VM reachable at `192.168.83.16` (ping test)
- [ ] SSH accessible (`ssh root@192.168.83.16`)
- [ ] Services running (check with `systemctl`)

<!-- LLM: END OF DOCUMENT -->
