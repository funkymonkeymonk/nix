# Nix-Managed LLM Interface Setup Guide

This guide provides comprehensive instructions for setting up and managing a unified LLM interface using Nix configuration management and LiteLLM proxy service.

## Overview

This implementation provides a centralized, version-controlled approach to managing multiple LLM providers through a single interface. The system uses:

- **Nix flakes** for declarative configuration management
- **LiteLLM** as a unified proxy service for multiple LLM providers
- **Systemd** service management for production-ready deployment
- **Environment-based configuration** for secure API key management

## Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Applications  │───▶│  LiteLLM     │───▶│  LLM Providers  │
│   (Open WebUI)  │    │  Proxy       │    │  (OpenAI, Anthropic, etc.) │
└─────────────────┘    └──────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │  Nix Config  │
                       │  Management   │
                       └──────────────┘
```

### Key Components

1. **Nix Configuration** (`configs/litellm/config.nix`)
   - Declarative service definition
   - Environment variable management
   - Systemd service configuration

2. **LiteLLM Configuration** (`configs/litellm/config.yaml`)
   - Provider definitions and model mappings
   - Authentication and routing rules
   - Load balancing and failover settings

3. **Environment Variables** (`/etc/litellm.env`)
   - API keys and secrets
   - Provider-specific settings
   - Runtime configuration

## Quick Setup

### Prerequisites

- Nix with flakes enabled
- Systemd (for Linux systems)
- API keys for desired LLM providers

### Installation Steps

1. **Add LiteLLM configuration to your Nix flake:**
   ```bash
   # Add to your flake.nix outputs
   litellm = import ./configs/litellm;
   ```

2. **Configure environment variables:**
   ```bash
   sudo vim /etc/litellm.env
   ```
   Add your API keys:
   ```bash
   OPENAI_API_KEY=your_openai_key_here
   ANTHROPIC_API_KEY=your_anthropic_key_here
   ```

3. **Build and enable the service:**
   ```bash
   # Rebuild with LiteLLM service
   sudo nixos-rebuild switch --option extra-experimental-features nix-command
   ```

4. **Start the service:**
   ```bash
   sudo systemctl enable --now litellm
   ```

5. **Verify the service:**
   ```bash
   curl -X POST http://localhost:4000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Hello!"}]}'
   ```

## Configuration Management

### Nix Configuration Structure

The Nix configuration is located at `configs/litellm/config.nix` and includes:

- **Service Definition**: Systemd service configuration
- **Environment Setup**: Required environment variables and paths
- **Resource Limits**: Memory and CPU constraints
- **Logging**: Log rotation and management settings

### LiteLLM Configuration

The main configuration file `configs/litellm/config.yaml` defines:

- **Model List**: Available models and their provider mappings
- **Provider Settings**: Authentication and routing rules
- **General Settings**: Timeouts, retries, and fallback options

### Adding New Providers

1. **Update the YAML configuration:**
   ```yaml
   model_list:
     - model_name: "new-provider-model"
       litellm_params:
         model: "provider/model-name"
         api_base: "https://api.provider.com"
   ```

2. **Add environment variables:**
   ```bash
   NEW_PROVIDER_API_KEY=your_key_here
   ```

3. **Rebuild the service:**
   ```bash
   sudo nixos-rebuild switch
   ```

## Usage

### Direct API Access

The LiteLLM service exposes an OpenAI-compatible API at `http://localhost:4000`:

```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "max_tokens": 150
  }'
```

### Open WebUI Integration

Configure Open WebUI to use the LiteLLM proxy:

1. Set the API base URL to `http://localhost:4000`
2. Use any configured model name (e.g., `gpt-3.5-turbo`, `claude-3-sonnet`)
3. The proxy will route requests to the appropriate provider

### Available Models

The service provides access to multiple models through a unified interface:

- **OpenAI**: `gpt-3.5-turbo`, `gpt-4`, `gpt-4-turbo`
- **Anthropic**: `claude-3-sonnet`, `claude-3-haiku`
- **Local Models**: Ollama models when configured
- **Custom Providers**: Any provider supported by LiteLLM

## Service Management

### Systemd Commands

```bash
# Start the service
sudo systemctl start litellm

# Stop the service
sudo systemctl stop litellm

# Restart the service
sudo systemctl restart litellm

# Check service status
sudo systemctl status litellm

# View logs
sudo journalctl -u litellm -f

# Enable at boot
sudo systemctl enable litellm
```

### Configuration Reload

After modifying the LiteLLM configuration:

```bash
# Reload the service to apply changes
sudo systemctl reload litellm

# Or restart for full reload
sudo systemctl restart litellm
```

### Monitoring

Monitor service health and performance:

```bash
# Check if service is running
sudo systemctl is-active litellm

# View resource usage
sudo systemctl status litellm --no-pager

# Monitor logs for errors
sudo journalctl -u litellm --since "1 hour ago" -p err
```

## Troubleshooting

### Common Issues

1. **Service fails to start:**
   ```bash
   # Check service status for errors
   sudo systemctl status litellm
   
   # View detailed logs
   sudo journalctl -u litellm -n 50
   ```

2. **Authentication errors:**
   - Verify API keys in `/etc/litellm.env`
   - Check file permissions: `sudo chmod 600 /etc/litellm.env`
   - Ensure environment file is correctly formatted

3. **Model not found:**
   - Verify model is listed in `config.yaml`
   - Check provider API key is valid
   - Confirm provider service is available

4. **Connection refused:**
   - Ensure service is running: `sudo systemctl status litellm`
   - Check port availability: `netstat -tlnp | grep 4000`
   - Verify firewall settings

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Add to environment file
echo "LITELLM_LOG_LEVEL=DEBUG" | sudo tee -a /etc/litellm.env

# Restart service
sudo systemctl restart litellm

# View debug logs
sudo journalctl -u litellm -f
```

### Health Checks

Test service health:

```bash
# Basic connectivity test
curl -f http://localhost:4000/health || echo "Health check failed"

# Test model availability
curl -X POST http://localhost:4000/v1/models \
  -H "Content-Type: application/json" | jq '.data[].id'
```

## Version Control Benefits

### Git-Managed Configuration

Storing configuration in Git provides numerous advantages:

- **History Tracking**: All configuration changes are versioned and auditable
- **Rollback Capability**: Quickly revert to previous working configurations
- **Collaboration**: Share configurations across teams and environments
- **Automation**: Integrate with CI/CD pipelines for automated deployments
- **Documentation**: Configuration serves as living documentation

### Configuration Drift Prevention

With Nix declarative configuration:

- **Idempotent Deployments**: Multiple rebuilds produce identical results
- **Dependency Management**: All requirements are explicitly declared
- **Reproducibility**: Same configuration works across different machines
- **Atomic Updates**: Configuration changes are applied atomically

### Backup and Recovery

- **Configuration Backup**: Git repository serves as configuration backup
- **Disaster Recovery**: Quickly restore services from version-controlled configs
- **Environment Parity**: Maintain identical configurations across environments

## Security Considerations

### API Key Management

- **Environment Variables**: Store API keys in `/etc/litellm.env` with restricted permissions
- **File Permissions**: Ensure `chmod 600` on environment files
- **No Secrets in Git**: Never commit API keys or sensitive data to version control
- **Regular Rotation**: Establish schedule for API key rotation

### Network Security

- **Local Access Only**: Service binds to localhost by default
- **Firewall Configuration**: Restrict access to authorized networks
- **TLS Termination**: Use reverse proxy for HTTPS termination in production
- **Rate Limiting**: Configure provider-side rate limits where available

## Advanced Configuration

### Load Balancing

Configure multiple API keys for load balancing:

```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
      api_key: ["key1", "key2", "key3"]  # Round-robin rotation
```

### Fallback Configuration

Set up automatic fallback providers:

```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
      model_list: ["openai/gpt-3.5-turbo", "azure/gpt-35-turbo"]
      fallbacks: [{"anthropic/claude-3-sonnet": "anthropic/claude-3-haiku"}]
```

### Custom Headers

Add custom headers for providers:

```yaml
model_list:
  - model_name: "custom-model"
    litellm_params:
      model: "provider/model"
      custom_headers: {"X-Custom-Header": "value"}
```

## Performance Optimization

### Caching

Enable response caching:

```yaml
general_settings:
  cache: true
  cache_type: "simple"
  cache_time: 3600  # 1 hour
```

### Connection Pooling

Optimize connection settings:

```yaml
general_settings:
  num_retries: 3
  timeout: 60
  request_timeout: 60
  set_verbose: false
```

## Next Steps

### Production Deployment

1. **Monitoring Setup**: Configure Prometheus/Grafana for service monitoring
2. **Log Aggregation**: Set up centralized logging with ELK stack
3. **Backup Strategy**: Implement automated backup of configuration files
4. **Security Audit**: Review and harden security configurations

### Scaling Considerations

1. **Horizontal Scaling**: Deploy multiple LiteLLM instances behind load balancer
2. **Database Backend**: Configure Redis for distributed caching
3. **Geographic Distribution**: Deploy region-specific instances for latency reduction

### Integration Opportunities

1. **API Gateway**: Integrate with existing API gateway solutions
2. **Authentication**: Add JWT/OIDC authentication for multi-tenant usage
3. **Billing Integration**: Connect with billing systems for cost tracking

## Maintenance

### Regular Tasks

- **Weekly**: Check service logs for errors and performance issues
- **Monthly**: Review and rotate API keys as needed
- **Quarterly**: Update LiteLLM version and provider configurations
- **Annually**: Review and update security configurations

### Update Process

1. **Test Changes**: Use Nix dry-run to test configuration changes
2. **Backup**: Create backup of working configuration
3. **Apply Changes**: Rebuild with new configuration
4. **Verify**: Test service functionality after updates
5. **Monitor**: Watch for issues after deployment

This setup provides a robust, scalable, and maintainable solution for managing multiple LLM providers through a unified interface, with all configuration under version control and managed through Nix declarative configuration.