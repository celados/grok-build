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

## Landing a patch

A patch is not done when the rules match — it is done when a release carrying it
is installed locally. Finish every patch with this sequence:

1. `./build.sh --check` — re-verifies each seam against the *current* upstream
   head, which is usually ahead of whatever `sources/` was left at. Seam counts
   proved against a stale snapshot mean nothing.
2. Commit and push to `main`.
3. `gh workflow run sync-and-release.yml -f force_release=true`. **Pushing does
   not build anything.** The workflow triggers only on `schedule` and
   `workflow_dispatch`, and a scheduled run whose upstream SHA is unchanged exits
   as a no-op — so a patch-only commit never releases itself.
4. Watch the run to completion (`gh run watch`). A failure opens a maintenance
   issue instead of publishing.
5. `grok update`, then confirm `grok --version` reports the new build.

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
  closed on ID collisions. Bundled files load through the same tool via a
  relative `path` argument (traversal rejected, miss returns the file menu);
  the loaded output lists bundled files as relative paths and carries no
  absolute paths.
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

## Terminal: Otty keyboard protocol

`patches/otty-kkp*.yml` drop `Otty` from `TerminalName::is_capability_unclassified`.
Upstream groups it with `Unknown` for want of positive evidence, so
`kitty_skip_reason` reports `unknown_no_multiplexer` and the Kitty keyboard
protocol is never pushed. Without its disambiguate enhancement `Ctrl+M` is the
same byte as `Enter` (CR), which costs the agent-screen model picker, `Shift+Enter`,
and focus tracking. Otty documents KKP as on by default —
<https://docs.otty.sh/terminal-features/input#kitty-keyboard-protocol>.

The three accompanying rules retarget the upstream tests that assert the old
classification. `delivers_ime_as_bracketed_paste` matches `Otty` directly and is
deliberately left alone: it gates the payload-origin check that keeps a macOS IME
commit from being read as a clipboard paste. `otty-kkp-test-capability` asserts
that gate still holds, so a future widening of this patch fails loudly.
