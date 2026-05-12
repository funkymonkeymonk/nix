# PROMPTING-EXAMPLES.md - Effective Usage Patterns

## Basic Interactions

### System Information
"What's my current system status?"
- Check disk space, memory, uptime inside the VM
- Show OpenClaw service status
- Check Ollama connectivity

### File Operations
"Show me the contents of /var/lib/openclaw"
- List files, show sizes, recent modifications
- Read configuration files

### Web Queries
"Check if github.com is up"
- Use curl to test connectivity from the VM

## Advanced Patterns

### Deployment Tasks
"Update my OpenClaw configuration and redeploy"
```bash
# Edit configuration in the nix repo
cd ~/nix
# Make changes to targets/microvms/openclaw-vfkit.nix
# Deploy the changes
deploy .#openclaw-vm
```

### Troubleshooting
"The gateway isn't responding, check logs"
```bash
# Check service status
systemctl status openclaw-gateway

# View logs
journalctl -u openclaw-gateway -n 100

# Check Ollama connectivity
curl http://host:11434/api/tags
```

### Ollama Management
"What models are available in Ollama?"
```bash
curl http://host:11434/api/tags
```

"Test Ollama with a simple prompt"
```bash
curl http://host:11434/api/generate -d '{
  "model": "qwen3.5",
  "prompt": "Hello, are you working?"
}'
```

## Best Practices

### Be Specific
- Good: "Show me the last 10 lines of the gateway log"
- Vague: "Check the logs" (which logs?)

### Provide Context
- Good: "I just edited the flake, can you verify it evaluates?"
- Missing context: "Check if it's right"

### Ask for Confirmation
- Good: "I need to delete 3 files in /tmp. Proceed? (y/n)"
- Risky: (deletes without asking)

### Chain Operations
"Update the system: verify config, deploy, check status"
- Multi-step with verification at each stage

## Things I Handle Well
- NixOS configuration management
- File and system operations inside the VM
- Service management via systemd
- Ollama queries and model management
- Troubleshooting and diagnostics

## Things to Ask a Human
- Complex architectural decisions
- Security policy changes
- Irreversible destructive operations
- Changes to the host (protoman) system
- Personal or sensitive matters
