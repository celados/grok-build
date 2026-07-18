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

## Runtime: skill-by-name (Claude-style)

Upstream `grok-build` toolsets deliberately omit a Skill tool and instruct
models to open `SKILL.md` via `read_file` using the listed Absolute path.
Models (Grok, Kimi, …) commonly re-root that absolute path under the workspace
(`~/.agents/skills/…` → `workspace/.agents/skills/…`), which fails hard.

`patches/runtime/skill-by-name/` aligns the harness with Claude Code:

| Patch | Effect |
| --- | --- |
| `toolset.yml` | Register `OpenCodeSkillTool` in `default_grok_build_toolset` (workspace inherits) |
| `alias.yml` | Claude allowlist `Skill` → `ToolKind::Skill` / `skill` (not `Read`/`read_file`) |
| `listing.yml` | Listing header: call skill tool **by name**; Absolute path is diagnostic only |
| `read_file.yml` | Description: absolute paths must be passed VERBATIM; prefer skill tool for skills |
| `regression.yml` | Unit test that default + workspace toolsets include `skill` |

Apply is conditional (skip when upstream already satisfied). After install,
agents should load skills with `skill` + `name: "ctx"`, not path surgery.
