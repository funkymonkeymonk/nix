# Pi RTK Extension

[RTK](https://github.com/rtk-ai/rtk) (Rust Token Killer) integration for [Pi](https://pi.dev) coding agent. Reduces LLM token consumption by 60-90% on common dev commands.

## Overview

This Pi extension transparently intercepts bash tool calls and rewrites them to use RTK equivalents before execution. The LLM receives compressed, token-optimized output without any changes to your workflow.

**Example transformations:**
- `git status` → `rtk git status` (80% savings)
- `cargo test` → `rtk cargo test` (90% savings)
- `npm install` → `rtk npm install` (80% savings)

## Installation

### Prerequisites

- [Pi coding agent](https://pi.dev) installed
- [RTK](https://github.com/rtk-ai/rtk) installed (`brew install rtk` or see [RTK docs](https://github.com/rtk-ai/rtk#installation))

### Install from Git

```bash
# Clone to Pi extensions directory
git clone https://github.com/yourusername/pi-rtk.git ~/.pi/agent/extensions/pi-rtk

# Or install as a Pi package
pi install git:github.com/yourusername/pi-rtk
```

### Install from npm (when published)

```bash
pi install npm:pi-rtk
```

### Manual Installation

1. Copy `src/index.ts` to `~/.pi/agent/extensions/rtk.ts`
2. Restart Pi or run `/reload`

## Usage

Once installed, the extension works automatically. All supported bash commands are transparently rewritten to use RTK.

### Commands

- `/rtk-status` - Show RTK token savings statistics
- `/rtk-discover` - Find missed RTK savings opportunities

### Disabling RTK

Per-command:
```bash
RTK_DISABLED=1 git status  # Runs raw git status
```

Globally:
```bash
export RTK_DISABLED=1
```

## Supported Commands

The extension automatically rewrites these commands:

**Git:** `git status`, `git diff`, `git log`, `git add`, `git commit`, `git push`, `git pull`, `git show`

**GitHub CLI:** `gh pr`, `gh issue`, `gh run`

**File Operations:** `cat`, `head`, `tail`, `ls`, `find`, `grep`, `rg`

**Build Tools:** `cargo`, `npm`, `pnpm`, `yarn`, `make`, `cmake`

**Test Runners:** `vitest`, `jest`, `pytest`, `playwright`

**Linters:** `eslint`, `biome`, `ruff`, `golangci-lint`, `rubocop`

**Containers:** `docker`, `kubectl`

**Package Managers:** `pip`, `bundle`, `prisma`

**TypeScript:** `tsc`

**Formatting:** `prettier`

See [RTK documentation](https://github.com/rtk-ai/rtk#commands-rewritten) for the full list.

## How It Works

```
User/LLM: "git status"
  ↓
Pi bash tool call
  ↓
Pi RTK Extension intercepts
  ↓
rtk rewrite "git status" → "rtk git status"
  ↓
Modified command executes
  ↓
LLM receives: "ok main" (10 tokens instead of 2000+)
```

## Development

```bash
# Clone the repository
git clone https://github.com/yourusername/pi-rtk.git
cd pi-rtk

# Install dependencies
npm install

# Link for local testing
ln -s $(pwd) ~/.pi/agent/extensions/pi-rtk

# Test with Pi
pi -e ./src/index.ts
```

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [RTK](https://github.com/rtk-ai/rtk) - The token optimization tool
- [Pi](https://pi.dev) - The minimal terminal coding harness
