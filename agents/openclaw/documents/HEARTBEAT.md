# HEARTBEAT.md - Health and Monitoring

## Service Status
Check if OpenClaw gateway is running:
```bash
systemctl status openclaw-gateway
```

## Logs
View recent gateway logs:
```bash
journalctl -u openclaw-gateway -n 50
```

## Restart Service
If the gateway needs restarting:
```bash
sudo systemctl restart openclaw-gateway
```

## Update Configuration
After editing the Nix configuration:
```bash
# From the host (protoman)
deploy .#openclaw-vm
```

## VM Management
Check VM status on host (protoman):
```bash
# Check if VM process is running
ps aux | grep vfkit | grep openclaw

# View VM logs
ssh -p 2222 root@192.168.1.192 "journalctl -n 20"
```

## Common Issues
- **Service not starting**: Check logs for config errors
- **Bot not responding**: Verify Discord token and chat ID
- **Ollama not accessible**: Ensure Ollama is running on host at http://host:11434
- **Tools not found**: Ensure packages are in the Nix closure

## Health Check
A healthy system should show:
- Gateway service: "active (running)" via systemctl
- Bot responds to messages
- Logs show no errors
- Can reach Ollama on host: `curl http://host:11434/api/tags`

## Recovery
If something breaks:
1. Check logs: `journalctl -u openclaw-gateway -f`
2. Restart service: `sudo systemctl restart openclaw-gateway`
3. Redeploy if needed: `deploy .#openclaw-vm`
4. Check Ollama on host: `ssh monkey@192.168.1.192 "ollama list"`
