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

The scheduled workflow compares `upstream/main` with the last entry in
`versions.jsonl`. A changed SHA triggers one patched build and release; an
unchanged SHA is a no-op. Failed builds open an issue and do not advance the
version mapping.

## Runtime: read_file absolute path

Skill loading is ordinary `read_file` with the Absolute path from the skill
list. Models sometimes rewrite absolute paths under the workspace.

`patches/runtime/read-file-absolute/` (conditional) only hardens the
`read_file` tool description and `target_file` param: absolute paths must
be passed unchanged.
