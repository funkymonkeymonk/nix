# RTK Token Optimization

Use RTK-prefixed commands for token-efficient output:

| Standard Command | RTK Equivalent | Token Savings |
|------------------|----------------|---------------|
| `git status` | `rtk git status` | ~80% |
| `git diff` | `rtk git diff` | ~75% |
| `git log` | `rtk git log` | ~80% |
| `git push` | `rtk git push` | ~92% |
| `ls` | `rtk ls` | ~80% |
| `cat <file>` | `rtk read <file>` | ~70% |
| `grep` | `rtk grep` | ~80% |
| `cargo test` | `rtk cargo test` | ~90% |
| `npm test` | `rtk npm test` | ~90% |
| `ruff check` | `rtk ruff check` | ~80% |
| `pytest` | `rtk pytest` | ~90% |
| `docker ps` | `rtk docker ps` | ~80% |

Check savings: `rtk gain` or `rtk gain --graph`
