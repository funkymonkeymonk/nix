# LiteLLM Configuration Documentation

This directory contains the LiteLLM configuration for providing a unified interface to multiple LLM providers through Nix-managed services.

## Configuration Structure

### Files Overview

```
configs/litellm/
├── config.nix          # Nix service definition and configuration
├── config.yaml         # LiteLLM provider and model configuration
├── default.nix         # Nix module entry point
└── README.md           # This documentation
```

### Nix Configuration (`config.nix`)

The Nix configuration defines:
- **Systemd Service**: LiteLLM service management
- **Environment Setup**: Required environment variables and paths
- **Resource Management**: Memory limits, user permissions, and security settings
- **Log Management**: Log rotation and persistence configuration

#### Key Components

```nix
{
  systemd.services.litellm = {
    description = "LiteLLM API Proxy Service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      ExecStart = "${pkgs.litellm}/bin/litellm --config ${configFile}";
      EnvironmentFile = "/etc/litellm.env";
      User = "litellm";
      Group = "litellm";
      Restart = "always";
      RestartSec = 5;
      MemoryLimit = "2G";
    };
  };
  
  environment = {
    etc."litellm.env".source = envFile;
  };
}
```

### LiteLLM Configuration (`config.yaml`)

The main configuration file defines available models, providers, and routing rules.

#### Configuration Sections

**General Settings**
```yaml
general_settings:
  master_key: "sk-1234"              # Optional master key for authentication
  database_url: "sqlite:///litellm.db"  # Usage tracking and caching
  cache: true                        # Enable response caching
  cache_type: "simple"               # Simple in-memory cache
  cache_time: 3600                   # Cache duration (seconds)
  set_verbose: false                 # Detailed logging
```

**Model List**
```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
      api_base: "https://api.openai.com"
```

## Supported Providers

### OpenAI

**Configuration:**
```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
  
  - model_name: "gpt-4"
    litellm_params:
      model: "openai/gpt-4"
  
  - model_name: "gpt-4-turbo"
    litellm_params:
      model: "openai/gpt-4-turbo-preview"
```

**Environment Variables:**
```bash
OPENAI_API_KEY=sk-your-openai-key
OPENAI_API_BASE=https://api.openai.com  # Optional, uses default
```

### Anthropic Claude

**Configuration:**
```yaml
model_list:
  - model_name: "claude-3-sonnet"
    litellm_params:
      model: "anthropic/claude-3-sonnet-20240229"
  
  - model_name: "claude-3-haiku"
    litellm_params:
      model: "anthropic/claude-3-haiku-20240307"
  
  - model_name: "claude-3-opus"
    litellm_params:
      model: "anthropic/claude-3-opus-20240229"
```

**Environment Variables:**
```bash
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key
```

### Azure OpenAI

**Configuration:**
```yaml
model_list:
  - model_name: "azure-gpt-35-turbo"
    litellm_params:
      model: "azure/gpt-35-turbo"
      api_base: "https://your-resource.openai.azure.com"
      api_version: "2023-07-01-preview"
```

**Environment Variables:**
```bash
AZURE_API_KEY=your-azure-api-key
AZURE_API_BASE=https://your-resource.openai.azure.com
AZURE_API_VERSION=2023-07-01-preview
```

### Google Gemini

**Configuration:**
```yaml
model_list:
  - model_name: "gemini-pro"
    litellm_params:
      model: "google/gemini-pro"
```

**Environment Variables:**
```bash
GOOGLE_API_KEY=your-google-api-key
```

### Cohere

**Configuration:**
```yaml
model_list:
  - model_name: "command"
    litellm_params:
      model: "cohere/command"
  
  - model_name: "command-nightly"
    litellm_params:
      model: "cohere/command-nightly"
```

**Environment Variables:**
```bash
COHERE_API_KEY=your-cohere-api-key
```

### Ollama (Local Models)

**Configuration:**
```yaml
model_list:
  - model_name: "ollama-llama2"
    litellm_params:
      model: "ollama/llama2"
      api_base: "http://localhost:11434"
  
  - model_name: "ollama-mistral"
    litellm_params:
      model: "ollama/mistral"
      api_base: "http://localhost:11434"
```

**Environment Variables:**
```bash
# No API key required for local Ollama
```

## Adding New Models

### Step 1: Update Configuration

Add the new model to `config.yaml`:

```yaml
model_list:
  # Existing models...
  
  - model_name: "new-provider-model"
    litellm_params:
      model: "provider/model-name"
      api_base: "https://api.provider.com"  # If required
      api_version: "v1"                     # If required
```

### Step 2: Set Environment Variables

Add required environment variables to `/etc/litellm.env`:

```bash
NEW_PROVIDER_API_KEY=your-api-key-here
NEW_PROVIDER_API_BASE=https://api.provider.com  # Optional
```

### Step 3: Test Configuration

Test the new model:

```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "new-provider-model",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Step 4: Reload Service

Apply changes:

```bash
sudo systemctl restart litellm
```

## Advanced Configuration

### Load Balancing

Configure multiple API keys for load balancing:

```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
      api_key: ["sk-key1", "sk-key2", "sk-key3"]  # Round-robin
```

### Fallback Providers

Set up automatic failover:

```yaml
model_list:
  - model_name: "gpt-3.5-turbo"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
      fallbacks: [{"anthropic/claude-3-haiku": "anthropic/claude-3-haiku"}]
```

### Model Aliases

Create user-friendly model names:

```yaml
model_list:
  - model_name: "fast-chat"
    litellm_params:
      model: "openai/gpt-3.5-turbo"
  
  - model_name: "smart-chat"
    litellm_params:
      model: "openai/gpt-4"
  
  - model_name: "creative-chat"
    litellm_params:
      model: "anthropic/claude-3-sonnet"
```

### Custom Headers

Add provider-specific headers:

```yaml
model_list:
  - model_name: "custom-model"
    litellm_params:
      model: "provider/model"
      custom_headers: {
        "X-Custom-Header": "value",
        "Authorization": "Bearer custom-token"
      }
```

### Request/Response Transformation

Modify requests and responses:

```yaml
model_list:
  - model_name: "transformed-model"
    litellm_params:
      model: "provider/model"
      transform_requests: true
      request_transformations: [
        {
          type: "replace",
          param: "model",
          value: "provider-internal-model-name"
        }
      ]
```

## Configuration Testing

### Validation Command

Validate LiteLLM configuration:

```bash
litellm --config config.yaml --dry_run
```

### Model Testing

Test each configured model:

```bash
# Test OpenAI models
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Test"}]}'

# Test Anthropic models
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-3-sonnet", "messages": [{"role": "user", "content": "Test"}]}'

# Test model list endpoint
curl http://localhost:4000/v1/models
```

### Performance Testing

Benchmark configuration performance:

```bash
# Concurrent requests test
for i in {1..10}; do
  curl -X POST http://localhost:4000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Test '$i'"}]}' &
done
wait
```

## Security Notes

### API Key Management

**Best Practices:**
- Store API keys in `/etc/litellm.env` with `chmod 600` permissions
- Use environment-specific API keys when possible
- Rotate API keys regularly
- Monitor API key usage and costs
- Never commit API keys to version control

**Example Secure Setup:**
```bash
# Set proper permissions
sudo chmod 600 /etc/litellm.env
sudo chown litellm:litellm /etc/litellm.env

# Verify permissions
ls -la /etc/litellm.env
```

### Network Security

**Recommended Configurations:**
- Bind to localhost (`127.0.0.1`) by default
- Use reverse proxy (nginx/caddy) for HTTPS termination
- Implement rate limiting at the reverse proxy level
- Configure firewall rules to restrict access

**Example Nginx Configuration:**
```nginx
server {
    listen 443 ssl;
    server_name llm.example.com;
    
    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Authentication

**Master Key Setup:**
```yaml
general_settings:
  master_key: "sk-secure-master-key-here"
```

**Usage with Master Key:**
```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-secure-master-key-here" \
  -d '{"model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Troubleshooting

### Common Configuration Issues

**1. Service Fails to Start:**
```bash
# Check service logs
sudo journalctl -u litellm -n 50

# Common causes:
# - Missing environment variables
# - Invalid YAML syntax
# - Port conflicts
# - Permission issues
```

**2. Model Not Available:**
```bash
# Verify model in configuration
grep -A 10 "model_name:" config.yaml

# Test model endpoint
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "model-name", "messages": [{"role": "user", "content": "Test"}]}'
```

**3. Authentication Errors:**
```bash
# Check environment variables
cat /etc/litellm.env

# Test API key validity
curl -H "Authorization: Bearer $API_KEY" https://api.provider.com/v1/models
```

### Debug Mode

Enable detailed logging:

```yaml
general_settings:
  set_verbose: true
  debug: true
```

Or via environment variable:
```bash
LITELLM_LOG_LEVEL=DEBUG systemctl restart litellm
```

### Configuration Validation

Validate YAML syntax:
```bash
python -c "import yaml; yaml.safe_load(open('config.yaml'))"
```

Validate LiteLLM configuration:
```bash
litellm --config config.yaml --dry_run
```

## Performance Optimization

### Caching Configuration

Enable response caching for improved performance:

```yaml
general_settings:
  cache: true
  cache_type: "simple"           # or "redis" for distributed
  cache_time: 3600              # Cache duration in seconds
  cache_key_fn: "user_and_model" # Cache key strategy
```

### Connection Management

Optimize connection settings:

```yaml
general_settings:
  num_retries: 3                # Number of retry attempts
  timeout: 60                   # Request timeout
  request_timeout: 60           # Connection timeout
  max_budget: 100.0            # Budget limit (USD)
  budget_duration: "30d"        # Budget period
```

### Resource Limits

Configure Nix service limits:

```nix
serviceConfig = {
  MemoryLimit = "4G";           # Memory limit
  CPUQuota = "200%";            # CPU limit (2 cores)
  TasksMax = 100;              # Max concurrent tasks
  LimitNOFILE = 65536;         # Max file descriptors
};
```

## Migration Guide

### From Direct Provider Integration

When migrating from direct provider API calls to LiteLLM:

1. **Update Base URL:** Change from `https://api.provider.com` to `http://localhost:4000`
2. **Model Names:** Use configured model names instead of provider-specific names
3. **Authentication:** Switch to LiteLLM authentication (master key if configured)
4. **Headers:** Remove provider-specific headers, add LiteLLM headers as needed

### Example Migration

**Before:**
```bash
curl -X POST https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer sk-openai-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-3.5-turbo", "messages": [...]}'
```

**After:**
```bash
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-master-key" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-3.5-turbo", "messages": [...]}'
```

This configuration provides a comprehensive, secure, and performant LiteLLM setup that integrates seamlessly with Nix system management while supporting multiple LLM providers through a unified interface.