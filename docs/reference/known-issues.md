---
title: "Known Issues"
description: "Known limitations of the local oMLX and Bifrost stack"
type: reference
---

# Known Issues

## Xcode Metal Toolchain Mounting

Xcode 26 can report the Metal Toolchain as installed while failing to mount
its Cryptex. In that state `xcrun metal -v` reports that the toolchain is
missing. This affects optional native oMLX kernel builds, not ordinary MLX
runtime GPU execution.

Verify the state with:

```bash
env -u DEVELOPER_DIR -u SDKROOT /usr/bin/xcodebuild -showComponent metalToolchain
env -u DEVELOPER_DIR -u SDKROOT /usr/bin/xcrun --sdk macosx metal -v
```

## Long Prompts

Long agent prompts can have high first-token latency. oMLX's continuous
batching and tiered KV cache reduce repeated-prefix work, but generation still
scales with the model size and context length.
