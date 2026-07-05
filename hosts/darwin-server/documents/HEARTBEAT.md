# HEARTBEAT.md - Health and Monitoring

## Service Status
Check if OpenClaw gateway is running:
```bash
launchctl print gui/$UID/com.steipete.openclaw.gateway | grep state
```

## Logs
View recent gateway logs:
```bash
tail -50 /tmp/openclaw/openclaw-gateway.log
```

## Restart Service
If the gateway needs restarting:
```bash
launchctl kickstart -k gui/$UID/com.steipete.openclaw.gateway
```

## Update Configuration
After editing flake.nix:
```bash
cd ~/code/openclaw-local
home-manager switch --flake .#monkey
```

## Common Issues
- **Service not starting**: Check logs for config errors
- **Bot not responding**: Verify Telegram token and chat ID
- **Tools not found**: Ensure plugins are enabled in flake.nix

## Health Check
A healthy system should show:
- Gateway service: "state = running"
- Bot responds to /start command
- Logs show no errors
- Home Manager generation exists

## Recovery
If something breaks:
1. Check logs: `tail -f /tmp/openclaw/openclaw-gateway.log`
2. Rollback: `home-manager switch --rollback`
3. Restart: `launchctl kickstart -k gui/$UID/com.steipete.openclaw.gateway`
