---
title: "Known Issues & Tracked Upstream Bugs"
description: "Active upstream issues affecting the LLM stack, with workarounds and tracking status"
type: reference
---

# Known Issues & Tracked Upstream Bugs

This document tracks upstream bugs and architectural limitations that affect the local LLM stack. Each entry includes the upstream issue link, impact assessment, current workaround, and expected resolution path.

## Active Issues

### vllm-mlx: Prefix cache crash with large prompts

| | |
|---|---|
| **Upstream** | [waybarrios/vllm-mlx#178](https://github.com/waybarrios/vllm-mlx/issues/178) |
| **Status** | Open |
| **Severity** | High (crash) |
| **First observed** | 2026-01 |
| **Affected configs** | `enableContinuousBatching = true` + `enablePrefixCache = true` + prompts >19k tokens |

**Symptom:** vllm-mlx segfaults during prefill when `--enable-prefix-cache` is active and the prompt exceeds ~19k tokens. Server log shows `mid_prefill_cache` being enabled internally, which re-enables chunked prefill even when `--chunked-prefill-tokens 0` was passed.

**Workaround:** Set `chunkedPrefillTokens = 0` in the Nix target config. The generated launch script passes `--chunked-prefill-tokens 0` explicitly. This disables chunked prefill entirely, preventing the internal re-enable path from triggering.

**Risks of workaround:**
- No chunked prefill means very large prompts are processed in a single GPU dispatch, which can spike memory usage
- If memory pressure causes OOM, the only fallback is to reduce prompt size (trim tools or conversation history)

**Expected resolution:** Upstream fix to respect `--chunked-prefill-tokens 0` when prefix cache is enabled, or to gate `mid_prefill_cache` behind a separate flag.

---

### vllm-mlx: No intra-session prefix reuse in SimpleEngine

| | |
|---|---|
| **Upstream** | [waybarrios/vllm-mlx#567](https://github.com/waybarrios/vllm-mlx/issues/567) |
| **PR** | [waybarrios/vllm-mlx#574](https://github.com/waybarrios/vllm-mlx/pull/574) (open) |
| **Status** | PR open, not merged |
| **Severity** | High (performance) |
| **First observed** | 2026-01 |
| **Affected configs** | Default `SimpleEngine` mode (no `--continuous-batching`) |

**Symptom:** In a multi-turn conversation, every request re-prefills the entire message history from scratch. The system-prompt KV snapshot (PR #523) only helps when the *exact same* prefix repeats — it produces a miss as soon as the conversation grows by even one token.

**Measured impact:** Qwen3-Coder-30B-A3B with ~40K system+tools prefix:
- Turn 1: 54s (cold)
- Turn 2: 111s (warm model, full prefill again)
- System KV cache logs: `MISS` with a different hash every turn

**Workaround:** Switch to `BatchedEngine` (`enableContinuousBatching = true`) with `enablePrefixCache = true`. BatchedEngine uses `PagedCacheManager` with block-level prefix sharing, which reuses KV cache across turns in the same conversation.

**Trade-offs of workaround:**
- BatchedEngine adds scheduler overhead (~10–20% per-request throughput reduction)
- Requires chunked prefill workaround (issue #178 above) for large prompts
- PR #574's trie-based cache (when merged) would bring similar benefits to SimpleEngine without the batching overhead

**Expected resolution:** Merge of PR #574 (SimpleEngine prefix trie cache) or adoption of the `LRUPromptCache.fetch_nearest_cache` primitive in the MLLM text routing path.

---

### vllm-mlx: MLLM text routing disables system KV snapshot

| | |
|---|---|
| **Upstream** | Hardcoded probe in `SimpleEngine.start()` |
| **Local patch** | `snapshot-rotating-kv-cache.patch` (combined with RotatingKVCache meta_state fix) |
| **Status** | Patched locally; upstream still hardcodes `isinstance(c, KVCache)` |
| **Severity** | Medium (performance) |
| **First observed** | 2026-03 |
| **Affected configs** | Qwen models loaded with `MLLM=True` (auto-detected for vision models) |

**Symptom:** vllm-mlx loads Qwen3.5/3.6/3.8 as MLLM (`MLLM=True`) even for text-only requests, then routes them through `mlx_vlm` → extracted `TextModel`. The system KV cache probe in `_stream_generate_text` hardcodes `isinstance(c, KVCache)` and rejects `ArraysCache` entries, disabling snapshots for all hybrid models.

**Local patch:** `packages/vllm-mlx/snapshot-rotating-kv-cache.patch` replaces the hardcoded probe with `self._cache_class_is_system_snapshot_safe(c)`, which already knows `ArraysCache` is safe.

**Upstream gap:** The upstream code at `vllm_mlx/engine/simple.py:~518` still uses the hardcoded `isinstance(c, KVCache)` check. The patch must be reapplied on every vllm-mlx version bump until upstream aligns the probe with `_cache_class_is_system_snapshot_safe`.

**Expected resolution:** Upstream acceptance of the probe alignment fix (trivial one-line change), or migration to BatchedEngine where prefix caching uses a different code path.

---

### vllm-mlx: RotatingKVCache snapshot missing meta_state

| | |
|---|---|
| **Upstream** | Missing `meta_state` capture/restore in `.state` |
| **Local patch** | `packages/vllm-mlx/snapshot-rotating-kv-cache.patch` |
| **Status** | Patched locally; upstream still only copies `.state` |
| **Severity** | Medium (correctness) |
| **First observed** | 2026-03 |
| **Affected configs** | Models with sliding-window attention (Gemma 4) + system KV cache enabled |

**Symptom:** Gemma 4 models use `RotatingKVCache` for sliding-window layers. The upstream `_snapshot_prompt_cache` / `_restore_prompt_cache` only copies `.state`, missing the `meta_state` cursor metadata. Restoring without the cursor causes the KV cache to desynchronize, potentially producing garbled output.

**Local patch:** `packages/vllm-mlx/snapshot-rotating-kv-cache.patch` adds `_cache_entry_snapshot()` and `_restore_prompt_cache()` methods that capture both `state` and `meta_state` for cache entries that expose it.

**Upstream gap:** mlx-lm's `RotatingKVCache` stores cursor position in `meta_state`, but vllm-mlx's snapshot/restore infrastructure was designed before `meta_state` existed. The patch is necessary until upstream extends the snapshot contract.

**Expected resolution:** Upstream vllm-mlx adoption of the `_cache_entry_snapshot` / `_restore_prompt_cache` split, or mlx-lm adding first-class snapshot support for `meta_state`.

---

### Bifrost: No conversation-level KV cache persistence

| | |
|---|---|
| **Upstream** | Bifrost `semantic_cache` plugin |
| **Status** | By design (response cache, not KV cache) |
| **Severity** | Medium (architectural limitation) |
| **Affected configs** | All Bifrost configurations |

**Symptom:** Bifrost's cache stores completed *responses*, not KV cache state. A cache hit only occurs when an identical request is sent again. Growing conversations never hit because every turn has a different message list.

**Why this is expected:** Bifrost is a gateway/proxy — it sees HTTP requests, not model internals. KV cache persistence is an inference-engine concern, not a gateway concern. Bifrost correctly delegates this to the upstream (vllm-mlx).

**No workaround needed:** The correct fix is at the inference layer (vllm-mlx prefix caching, issues #178/#567 above). Bifrost's timeout (`requestTimeout`) should be set >= vllm-mlx's timeout so it doesn't abort requests that are still prefill/working.

---

## Resolved Issues

### vllm-mlx: Terminal finish_reason missing in streaming

| | |
|---|---|
| **Upstream** | [waybarrios/vllm-mlx#673](https://github.com/waybarrios/vllm-mlx/pull/673) |
| **Status** | ✅ Merged in commit `61c78dc` (2026-08-15) |
| **Local fix** | Bumped `packages/vllm-mlx/default.nix` to latest main |

**Symptom:** Gemma 4 tool parser suppressed the terminal delta (just `<turn|>`), so the stream ended with `finish_reason=null` instead of `finish_reason=tool_calls`. Pi and other strict OpenAI clients retried the turn.

**Resolution:** Updated vllm-mlx to commit `61c78dc` which includes the merged PR #673. The fix tracks whether any emitted chunk carried a non-null `finish_reason`, and emits a terminal chunk after the streaming loop if the engine's finished output was suppressed by a parser.

---

## Tracking Checklist

- [ ] vllm-mlx#178 — prefix cache + large prompt crash
- [ ] vllm-mlx#567 — intra-session prefix reuse in SimpleEngine
- [ ] vllm-mlx#574 — merge of SimpleEngine prefix trie cache
- [ ] vllm-mlx upstream — accept MLLM text routing probe alignment (`mllm-text-route-arrays-cache.patch`)
- [ ] vllm-mlx upstream — accept RotatingKVCache meta_state snapshot (`snapshot-rotating-kv-cache.patch`)

## See Also

- [LLM Stack Reference](llm-stack.md) — Architecture, configuration, and operations
- [Configure the LLM Stack](../how-to/configure-llm-stack.md) — How-to guide with troubleshooting
