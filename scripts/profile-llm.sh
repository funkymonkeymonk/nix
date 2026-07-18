#!/usr/bin/env bash
# LLM Profiling Harness
# Profiles local LLM inference performance using vllm-mlx-bench
# and writes structured results to a gitignored directory.
#
# Usage: profile-llm.sh <model-id> [options]
#   MODEL: Model ID to profile (e.g., gemma4-31b, gemma4-e4b)
#   Options:
#     --prompts N       Number of prompts to run (default: 5)
#     --max-tokens N    Max tokens per response (default: 256)
#     --output-dir DIR  Directory for results (default: ./profiling)
#     --force           Skip resource constraint warnings
#
# Examples:
#   profile-llm.sh gemma4-31b
#   profile-llm.sh gemma4-e4b --prompts 10 --max-tokens 512

set -uo pipefail
# Ignore SIGPIPE so progress bars with \r don't kill the script
# when the parent terminal buffer is full.
trap '' PIPE

# Configuration
DEFAULT_PROMPTS=5
DEFAULT_MAX_TOKENS=256
DEFAULT_OUTPUT_DIR="${LLM_PROFILE_DIR:-./profiling}"
VLLM_MLX_URL="${VLLM_MLX_URL:-http://localhost:8300}"
BIFROST_URL="${BIFROST_URL:-http://localhost:8081}"

# Colors for terminal output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
MODEL=""
PROMPTS="$DEFAULT_PROMPTS"
MAX_TOKENS="$DEFAULT_MAX_TOKENS"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
FORCE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --prompts)
      PROMPTS="$2"
      shift 2
      ;;
    --max-tokens)
      MAX_TOKENS="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 <model-id> [--prompts N] [--max-tokens N] [--output-dir DIR] [--force]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$MODEL" ]]; then
        MODEL="$1"
      else
        echo "Only one model ID allowed" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$MODEL" ]]; then
  echo "Usage: $0 <model-id> [--prompts N] [--max-tokens N] [--output-dir DIR] [--force]" >&2
  echo "" >&2
  echo "Available models (from vllm-mlx $VLLM_MLX_URL):" >&2
  curl -s "$VLLM_MLX_URL/v1/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || echo "  (cannot reach vllm-mlx)" >&2
  exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULT_FILE="$OUTPUT_DIR/${MODEL}-${TIMESTAMP}.json"
LOG_FILE="$OUTPUT_DIR/${MODEL}-${TIMESTAMP}.log"
REPORT_FILE="$OUTPUT_DIR/${MODEL}-${TIMESTAMP}.md"

# Logging helper — tee failure must not abort the script (pipefail + SIGPIPE)
log() {
  local msg="$1"
  echo -e "$msg" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "$msg"
}

# ============================================================================
# System Resource Analysis
# ============================================================================

check_resources() {
  log "${BLUE}=== System Resource Analysis ===${NC}"

  # Total RAM
  local total_ram_gb
  total_ram_gb=$(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024}')
  log "Total RAM: ${total_ram_gb} GB"

  # Current vllm-mlx RSS
  local vllm_pid
  vllm_pid=$(lsof -ti:8300 2>/dev/null | head -1)
  VLLM_PID="$vllm_pid"
  local vllm_rss_gb=0
  if [[ -n "$vllm_pid" ]]; then
    vllm_rss_gb=$(ps -o rss= -p "$vllm_pid" 2>/dev/null | awk '{print $1/1024/1024}')
    log "vllm-mlx PID: $vllm_pid, RSS: ${vllm_rss_gb} GB"
  else
    log "${RED}WARNING: vllm-mlx not running on port 8300${NC}"
  fi

  # Available memory estimate (free + inactive pages on macOS)
  local available_gb
  if command -v vm_stat >/dev/null 2>&1; then
    available_gb=$(vm_stat | awk '
      /Pages free/ { free = $3 }
      /Pages inactive/ { inactive = $3 }
      /Pages active/ { active = $3 }
      END {
        gsub(/\\./, "", free)
        gsub(/\\./, "", inactive)
        gsub(/\\./, "", active)
        total = (free + inactive) * 16384 / 1024 / 1024 / 1024
        printf "%.1f", total
      }
    ')
    log "Available memory (free+inactive): ${available_gb} GB"
  else
    available_gb=$(echo "$total_ram_gb - $vllm_rss_gb" | bc)
    log "Estimated available: ${available_gb} GB"
  fi

  # CPU info
  local cpu_cores
  cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "unknown")
  log "Physical CPU cores: $cpu_cores"

  # Model memory estimation from config
  local estimated_model_gb=0
  # Try to get from running config
  local config_yaml
  config_yaml="$HOME/.config/vllm-mlx/registry.yaml"
  if [[ -f "$config_yaml" ]]; then
    estimated_model_gb=$(grep -A5 "name: ${MODEL}" "$config_yaml" 2>/dev/null | grep "estimated_memory_gb" | awk '{print $2}' || echo "0")
  fi

  if [[ "$estimated_model_gb" == "0" || -z "$estimated_model_gb" ]]; then
    # Fallback: estimate from model name
    case "$MODEL" in
      *31b*|*30b*|*35b*|*26b*) estimated_model_gb=20 ;;
      *13b*|*14b*|*15b*) estimated_model_gb=10 ;;
      *7b*|*8b*) estimated_model_gb=6 ;;
      *4b*|*3b*) estimated_model_gb=3 ;;
      *e4b*) estimated_model_gb=5 ;;
      *) estimated_model_gb=5 ;;
    esac
    log "Estimated model memory (heuristic): ${estimated_model_gb} GB"
  else
    log "Estimated model memory (from config): ${estimated_model_gb} GB"
  fi

  # Resource constraint warnings
  local warnings=0

  # Check if model already loaded
  local model_loaded=false
  if [[ -n "$vllm_pid" ]]; then
    if curl -s "$VLLM_MLX_URL/v1/models" 2>/dev/null | grep -q "\"id\":\"$MODEL\""; then
      model_loaded=true
      log "${GREEN}Model '$MODEL' is registered in vllm-mlx${NC}"
    else
      log "${YELLOW}WARNING: Model '$MODEL' is NOT in the vllm-mlx registry${NC}"
      log "${YELLOW}         It must be added to the Nix config and the system rebuilt.${NC}"
      warnings=$((warnings + 1))
    fi
  fi

  # Check available memory for model
  local needed_gb
  needed_gb=$(echo "$estimated_model_gb + 5" | bc) # Model + overhead
  local available_num
  available_num=$(echo "$available_gb" | bc)

  if (( $(echo "$available_num < $needed_gb" | bc -l) )); then
    log "${RED}WARNING: Insufficient memory for reliable profiling${NC}"
    log "${RED}         Need ~${needed_gb} GB, have ~${available_gb} GB available${NC}"
    log "${RED}         Close other applications or reduce concurrent load${NC}"
    warnings=$((warnings + 1))
  elif (( $(echo "$available_num < $needed_gb + 10" | bc -l) )); then
    log "${YELLOW}WARNING: Memory is tight (${available_gb} GB available, need ~${needed_gb} GB)${NC}"
    log "${YELLOW}         Other apps may impact results${NC}"
    warnings=$((warnings + 1))
  fi

  # Check if vllm-mlx is under heavy load
  if [[ -n "$vllm_pid" ]]; then
    # Count recent "SimpleEngine serialized route is busy" errors = stuck requests
    local stuck_errors=0
    stuck_errors=$(tail -n 100 /tmp/vllm-mlx.err 2>/dev/null | grep -c "SimpleEngine serialized route is busy" || true)
    stuck_errors="${stuck_errors:-0}"
    if [[ "$stuck_errors" -gt 0 ]]; then
      log "${YELLOW}WARNING: vllm-mlx has $stuck_errors recent 'route is busy' errors${NC}"
      log "${YELLOW}         A model is likely stuck. Consider restarting vllm-mlx.${NC}"
      warnings=$((warnings + 1))
    fi
    # Count recent TIMEOUT warnings
    local timeout_count=0
    timeout_count=$(tail -n 100 /tmp/vllm-mlx.err 2>/dev/null | grep -c "TIMEOUT after" || true)
    timeout_count="${timeout_count:-0}"
    if [[ "$timeout_count" -gt 0 ]]; then
      log "${YELLOW}WARNING: $timeout_count recent timeout(s) in vllm-mlx${NC}"
      warnings=$((warnings + 1))
    fi
  fi

  if [[ "$warnings" -gt 0 && "$FORCE" != "true" ]]; then
    log ""
    log "${YELLOW}Found $warnings resource constraint warning(s).${NC}"
    log "${YELLOW}Use --force to run anyway, or fix the issues above.${NC}"
    exit 1
  fi

  log ""
}

# ============================================================================
# Model Loading
# ============================================================================

ensure_model() {
  log "${BLUE}=== Model Check: $MODEL ===${NC}"

  # Check if model is already registered
  local models_json
  models_json=$(curl -s "$VLLM_MLX_URL/v1/models" 2>/dev/null || echo '{"data":[]}')

  if echo "$models_json" | jq -e --arg m "$MODEL" '.data[] | select(.id == $m)' >/dev/null 2>&1; then
    log "${GREEN}Model '$MODEL' is registered${NC}"

    # Warm up with a tiny request to ensure it's in memory
    log "Warming up model with a single-token request..."
    local warmup_response
    warmup_response=$(curl -s -w "\n%{http_code}" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" \
      "$VLLM_MLX_URL/v1/chat/completions" 2>/dev/null || echo "000")

    local http_code
    http_code=$(echo "$warmup_response" | tail -1)
    if [[ "$http_code" == "200" ]]; then
      log "${GREEN}Model warmed up successfully${NC}"
    else
      log "${YELLOW}Warmup returned HTTP $http_code — model may still be loading${NC}"
    fi
  else
    log "${RED}ERROR: Model '$MODEL' is not in the vllm-mlx registry${NC}"
    log "${RED}Add it to myConfig.vllmMlx.models in your host config and rebuild.${NC}"
    log ""
    log "Currently available models:"
    echo "$models_json" | jq -r '.data[].id' | while read -r m; do
      log "  - $m"
    done
    exit 1
  fi

  log ""
}

# ============================================================================
# Benchmark Execution
# ============================================================================

run_benchmark() {
  log "${BLUE}=== Running Benchmark ===${NC}"
  log "Model:      $MODEL"
  log "Prompts:    $PROMPTS"
  log "Max tokens: $MAX_TOKENS"
  log "Output:     $RESULT_FILE"
  log ""

  # Find vllm-mlx-bench binary from the same store path as the running
  # vllm-mlx process (avoids picking an old/broken version).
  local bench_bin=""
  if [[ -n "$VLLM_PID" ]]; then
    local vllm_store
    vllm_store=$(ps -p "$VLLM_PID" -o args= 2>/dev/null | grep -o '/nix/store/[^/]*vllm-mlx[^/]*' | head -1)
    if [[ -n "$vllm_store" ]]; then
      bench_bin="${vllm_store}/bin/vllm-mlx-bench"
    fi
  fi
  # Fallback: search nix store
  if [[ -z "$bench_bin" ]] || [[ ! -x "$bench_bin" ]]; then
    bench_bin=$(find /nix/store -maxdepth 4 -name "vllm-mlx-bench" -executable 2>/dev/null | head -1)
  fi
  if [[ -z "$bench_bin" ]] || [[ ! -x "$bench_bin" ]]; then
    log "${RED}ERROR: vllm-mlx-bench not found in /nix/store${NC}"
    exit 1
  fi
  log "Using: $bench_bin"
  log ""

  # Resolve model path from registry
  local model_hf_path=""
  local config_yaml="$HOME/.config/vllm-mlx/registry.yaml"
  if [[ -f "$config_yaml" ]]; then
    model_hf_path=$(python3 -c "
import yaml, sys
try:
    with open('$config_yaml') as f:
        data = yaml.safe_load(f)
    for m in data.get('models', []):
        if m.get('name') == '$MODEL':
            print(m.get('path', ''))
            break
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)
  fi

  # vllm-mlx-bench expects a HuggingFace path, not a Nix store path.
  # Always use the HF path for the benchmark tool.
  if [[ -z "$model_hf_path" ]] || [[ "$model_hf_path" == /nix/store* ]]; then
    # Fallback: try to infer from common patterns
    case "$MODEL" in
      gemma4-31b) model_hf_path="mlx-community/gemma-4-31b-it-4bit" ;;
      gemma4-e4b) model_hf_path="mlx-community/gemma-4-e4b-it-4bit" ;;
      *) model_hf_path="" ;;
    esac
  fi

  if [[ -z "$model_hf_path" ]]; then
    log "${RED}ERROR: Cannot determine HuggingFace path for model '$MODEL'${NC}"
    log "${RED}Check ~/.config/vllm-mlx/registry.yaml${NC}"
    exit 1
  fi

  log "Resolved HF path: $model_hf_path"
  log ""

  # Run the benchmark
  log "Starting benchmark..."
  log "----------------------------------------"

  local bench_output
  bench_output=$(mktemp)
  local bench_exit=0

  # Run benchmark redirecting all output to a temp file.
  # SIGPIPE is trapped above so progress bars with \r don't kill the script.
  "$bench_bin" \
    --model "$model_hf_path" \
    --prompts "$PROMPTS" \
    --max-tokens "$MAX_TOKENS" \
    > "$bench_output" 2>&1 || bench_exit=$?

  # Show progress dots while it runs (keeps parent alive)
  # Actually the command blocks; dots only help if we background it.
  # For now, run directly since we trapped SIGPIPE.

  # Copy output to log for record
  cat "$bench_output" >> "$LOG_FILE" 2>/dev/null || true

  log "----------------------------------------"
  log ""

  if [[ "$bench_exit" -ne 0 ]]; then
    log "${RED}Benchmark exited with code $bench_exit${NC}"
    log "See $LOG_FILE for full output"
    cp "$bench_output" "$RESULT_FILE.txt" 2>/dev/null || true
    rm -f "$bench_output"
    exit 1
  fi

  # Parse results from output
  log "${GREEN}Benchmark completed${NC}"
  log ""

  # Extract key metrics from the bench output.
  # Use sed to pull the first numeric value after the label on each line.
  local ttft=""
  local gen_speed=""
  local total_time=""
  local tpot=""
  local peak_memory=""

  ttft=$(grep "TTFT (Time to First Token)" "$bench_output" 2>/dev/null | sed -E 's/.*TTFT \(Time to First Token\)[[:space:]]+([0-9.]+).*/\1/' || echo "")
  tpot=$(grep "TPOT (Time Per Output Token)" "$bench_output" 2>/dev/null | sed -E 's/.*TPOT \(Time Per Output Token\)[[:space:]]+([0-9.]+).*/\1/' || echo "")
  gen_speed=$(grep "Generation Speed" "$bench_output" 2>/dev/null | sed -E 's/.*Generation Speed[[:space:]]+([0-9.]+).*/\1/' || echo "")
  total_time=$(grep "^Total Time" "$bench_output" 2>/dev/null | sed -E 's/.*Total Time[[:space:]]+([0-9.]+).*/\1/' || echo "")
  peak_memory=$(grep "Process Memory (peak)" "$bench_output" 2>/dev/null | sed -E 's/.*Process Memory \(peak\)[[:space:]]+([0-9.]+).*/\1/' || echo "")

  # Build JSON result
  cat > "$RESULT_FILE" << EOF
{
  "model": "$MODEL",
  "model_path": "$model_hf_path",
  "timestamp": "$TIMESTAMP",
  "prompts": $PROMPTS,
  "max_tokens": $MAX_TOKENS,
  "system": {
    "total_ram_gb": $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024}'),
    "cpu_cores": $(sysctl -n hw.physicalcpu 2>/dev/null || echo "null"),
    "vllm_mlx_rss_gb": $(ps -o rss= -p "${VLLM_PID:-0}" 2>/dev/null | awk '{print $1/1024/1024}' || echo "null")
  },
  "metrics": {
    "ttft_ms": ${ttft:-null},
    "tpot_ms": ${tpot:-null},
    "generation_tok_s": ${gen_speed:-null},
    "total_time_s": ${total_time:-null},
    "peak_memory_gb": ${peak_memory:-null}
  },
  "raw_output_file": "${RESULT_FILE}.txt"
}
EOF

  # Save raw output
  cp "$bench_output" "${RESULT_FILE}.txt"
  rm "$bench_output"

  log "Results saved: $RESULT_FILE"
  log "Raw output:    ${RESULT_FILE}.txt"
}

# ============================================================================
# Generate Markdown Report
# ============================================================================

generate_report() {
  log "${BLUE}=== Generating Report ===${NC}"

  local total_ram
  total_ram=$(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024}')
  local cpu_cores
  cpu_cores=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "unknown")

  cat > "$REPORT_FILE" << EOF
# LLM Profiling Report: $MODEL

**Date:** $(date -r "$TIMESTAMP" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")
**Model:** $MODEL
**Prompts:** $PROMPTS
**Max Tokens:** $MAX_TOKENS

## System Configuration

| Property | Value |
|----------|-------|
| Total RAM | ${total_ram} GB |
| CPU Cores | $cpu_cores |
| vllm-mlx URL | $VLLM_MLX_URL |

## Results

See \`$RESULT_FILE\` for structured data.

## Raw Output

\`\`\`
$(cat "${RESULT_FILE}.txt" 2>/dev/null || echo "No raw output captured")
\`\`\`

---
*Generated by profile-llm.sh*
EOF

  log "Report saved: $REPORT_FILE"
  log ""
}

# ============================================================================
# Main
# ============================================================================

main() {
  log "${GREEN}╔══════════════════════════════════════╗${NC}"
  log "${GREEN}║     LLM Profiling Harness            ║${NC}"
  log "${GREEN}╚══════════════════════════════════════╝${NC}"
  log ""

  check_resources
  ensure_model
  run_benchmark
  generate_report

  log "${GREEN}=== Profiling Complete ===${NC}"
  log ""
  log "Results directory: $OUTPUT_DIR"
  log "  JSON:  $RESULT_FILE"
  log "  Raw:   ${RESULT_FILE}.txt"
  log "  Report: $REPORT_FILE"
  log ""
  log "To view: cat $RESULT_FILE | jq ."
}

main "$@"
