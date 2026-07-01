---
title: "Explanation"
description: "Background, design rationale, and internal architecture"
type: explanation-landing
audience: both
---

# Explanation

Understanding-oriented background reading. These documents do not walk you through tasks — they explain why the system is designed the way it is.

## Architecture and Design

| Document | What It Covers |
|----------|---------------|
| [Architecture](architecture.md) | Module composition, options, roles, targets, helpers |
| [Disposable Infrastructure](disposable-infrastructure.md) | Heirloom vs takeout-container machine management |
| [Testing Strategy](testing.md) | Eval tests, VM tests, CI pipeline design |

## Multi-Agent Development

| Document | What It Covers |
|----------|---------------|
| [JJ Mental Model](jj-mental-model.md) | Why jj replaces git for this repo; change model and commands |
| [Yaks and Workspaces](yaks-workspaces.md) | Task tracking, claim protocol, parallel sub-agent dispatch |
| [Agent Skills System](agent-skills.md) | Why AI skills are managed through Nix instead of plain files |

## LLM Infrastructure

| Document | What It Covers |
|----------|---------------|
| [LLM Stack Evolution](llm-stack-evolution.md) | Migration from Higgs + Ollama to vllm-mlx + Bifrost |

## Security

| Document | What It Covers |
|----------|---------------|
| [MicroVM Security Architecture](microvm-security-architecture.md) | Isolation guarantees and network controls for MicroVMs |
| [opnix Security Model](opnix-security.md) | How opnix fetches, writes, and protects secrets |
