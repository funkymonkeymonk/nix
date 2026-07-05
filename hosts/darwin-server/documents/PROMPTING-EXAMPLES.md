# PROMPTING-EXAMPLES.md - Effective Usage Patterns

## Basic Interactions

### System Information
"What's my current system status?"
- Check disk space, memory, uptime
- Show running services

### File Operations
"Show me the contents of ~/Documents"
- List files, show sizes, recent modifications

### Web Queries
"Check if github.com is up"
- Use curl to test connectivity

## Advanced Patterns

### Development Tasks
"Update my Nix flake and switch"
```
cd ~/code/openclaw-local
# Update inputs
nix flake update
# Switch to new generation
home-manager switch --flake .#monkey
```

### Troubleshooting
"The gateway isn't responding, check logs"
```
tail -100 /tmp/openclaw/openclaw-gateway.log
# Look for errors
launchctl print gui/$UID/com.steipete.openclaw.gateway | grep state
```

### System Maintenance
"Clean up old Nix generations"
```
# List generations
home-manager generations
# Delete older than 30 days
nix-collect-garbage --delete-older-than 30d
```

## Best Practices

### Be Specific
- Good: "Show me the last 10 lines of the gateway log"
- Vague: "Check the logs" (which logs?)

### Provide Context
- Good: "I just edited flake.nix, can you verify the syntax?"
- Missing context: "Check if it's right"

### Ask for Confirmation
- Good: "I need to delete 3 files: a.txt, b.txt, c.txt. Proceed? (y/n)"
- Risky: (deletes without asking)

### Chain Operations
"Update the system: pull latest config, update flake, switch, verify"
- Multi-step with verification at each stage

## Things I Handle Well
- Configuration management (Nix/home-manager)
- File and system operations
- Service management
- Development workflows
- Troubleshooting and diagnostics

## Things to Ask a Human
- Complex architectural decisions
- Security policy changes
- Irreversible destructive operations
- Personal or sensitive matters
