# Grok Build for macOS

Apple Silicon macOS build of [xAI Grok Build](https://github.com/xai-org/grok-build)
with its interactive permission and folder-trust gates removed.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/celados/grok-build/main/install.sh | bash
```

The installer downloads the latest GitHub Release directly, verifies that the
binary starts before replacing an existing installation, and configures PATH
for Fish, Zsh, or Bash. No repository clone or GitHub CLI is required.

## Update

```sh
grok update
```

The binary uses this repository's GitHub Releases as its only update channel.

## Build locally

```sh
brew install ast-grep dotslash
git clone https://github.com/celados/grok-build.git
cd grok-build
./build.sh --version 1.0.0 --install
```

`build.sh` checks out `xai-org/grok-build` into the ignored `sources/`
directory, requires every AST patch to match exactly once, builds a signed
macOS arm64 binary, and restores the upstream checkout afterwards.

Temporary upstream hotfixes live under `patches/runtime/<issue>/`. Each hotfix
defines its buggy seam, a recognized fixed postcondition, and a regression
test: the build applies it while needed, skips it when upstream satisfies the
postcondition, and fails on unknown source drift.

## Release policy

The scheduled GitHub Action polls `upstream/main` every 15 minutes. A changed
upstream SHA produces one new custom release; an unchanged SHA exits without
building (~15s no-op). The version-to-upstream mapping is recorded in
[versions.jsonl](versions.jsonl).

If upstream changes an AST seam, the workflow stops and opens a maintenance
issue rather than publishing a partially patched binary.

A failed build also commits [.ci-halt.md](.ci-halt.md) — the failing log tail
plus the run URL — and the scheduled poll skips every run while that file
exists, because retrying an unrepaired tree only burns the runner. Two ways
out, both of which require having looked at the record:

- delete `.ci-halt.md` from `main` to resume polling, or
- run the workflow manually (`workflow_dispatch` ignores the gate) to test a
  candidate fix; a successful build deletes the record itself.
