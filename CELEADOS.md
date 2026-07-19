---
type: Playbook
title: Celados Grok Build Distribution
description: Thin AST patch layer and macOS arm64 release channel for Grok Build.
status: active
when: Building, installing, releasing, or repairing the custom Grok distribution.
---

# Celados Grok Build Distribution

This is an independent distribution repository, not a source fork. It owns only
AST patches, build/release scripts, and the mapping between custom versions and
upstream commits. `sources/` is ignored and populated directly from
`xai-org/grok-build` at the requested SHA.

Each AST rule must match exactly once. Source drift therefore stops the release
instead of silently producing a partially patched binary.

## Local build

```sh
brew install ast-grep
./build.sh --version 1.0.0 --install
```

The installed binary lives at `~/.grok/bin/grok`. This distribution supports
only Apple Silicon macOS.

## Install and update

```sh
./install.sh
grok update
```

Both commands use releases from `celados/grok-build`.

## Upstream contract

The scheduled workflow polls `upstream/main` every 15 minutes and compares it
with the last entry in `versions.jsonl`. A changed SHA triggers one patched
build and release; an unchanged SHA is a no-op. Failed builds open an issue
and do not advance the version mapping.

Upstream cadence is not clock-aligned: `grokkybara[bot]` pushes
"Synced from monorepo" when the monorepo export runs (observed ~14–30h
between pushes, irregular UTC hours). Polling is the only hook we have —
we do not control `xai-org/grok-build` webhooks.

## Runtime: hash-id skill tool

The upstream skill listing exposes absolute paths but does not provide a skill
tool. These groups make model-facing skill loading deterministic without
teaching the model to synthesize paths:

- `patches/runtime/skill-id-base/`: stable six-hex IDs from the existing
  FNV-1a-32 helper (low 24 bits) and full-file character counts.
- `patches/runtime/skill-id-tool/`: registers the OpenCode skill tool in every
  skill-discovering toolset, exposes `id`, removes name fallback, and fails
  closed on ID collisions.
- `patches/runtime/skill-id-listing/`: renders id-keyed markdown entries
  (`- id: <hex>` / `description: [<name>] …`, incl. the names-only budget
  tier); the bracketed name is a display tag, the id is the only load handle.
  Per-entry absolute paths are dropped — the skill tool output already carries
  the base directory.
- `patches/runtime/skill-fuzzy-dedup/`: applies deliberate `[name,
  chars_length]` fuzzy dedup, migrates announcement/conditional/persisted state
  keys to IDs, and removes obsolete name-shadowing code.

Groups ①–③ depend only on the shared ⓪ ID helper and are otherwise independently
applicable/revertible. All rules are required seams: upstream drift stops the
build instead of silently producing a partial skill protocol. XML compatibility
listings remain outside this markdown-mode patch contract.
