#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$ROOT_DIR/sources"
UPSTREAM_URL="https://github.com/xai-org/grok-build.git"
UPSTREAM_REF="main"
VERSION=""
OUTPUT_DIR="$ROOT_DIR/dist"
INSTALL=false
CHECK_ONLY=false
PREPARE_ONLY=false

usage() {
  echo "Usage: ./build.sh [--prepare|--check] [--upstream-ref REF] [--version X.Y.Z] [--output-dir DIR] [--install]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare) PREPARE_ONLY=true; shift ;;
    --check) CHECK_ONLY=true; shift ;;
    --upstream-ref) UPSTREAM_REF="${2:?--upstream-ref requires a value}"; shift 2 ;;
    --version) VERSION="${2:?--version requires a value}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
    --install) INSTALL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v git >/dev/null || { echo "Missing required command: git" >&2; exit 1; }

prepare_sources() {
  if [[ ! -d "$SOURCES_DIR/.git" ]]; then
    mkdir -p "$SOURCES_DIR"
    git -C "$SOURCES_DIR" init
    git -C "$SOURCES_DIR" remote add origin "$UPSTREAM_URL"
  fi

  if [[ "$(git -C "$SOURCES_DIR" remote get-url origin)" != "$UPSTREAM_URL" ]]; then
    echo "sources/ origin must be $UPSTREAM_URL" >&2
    exit 1
  fi
  if git -C "$SOURCES_DIR" rev-parse --verify HEAD >/dev/null 2>&1 \
    && ! git -C "$SOURCES_DIR" diff --quiet HEAD --; then
    echo "Refusing to replace a modified sources/ checkout." >&2
    exit 1
  fi

  git -C "$SOURCES_DIR" fetch --depth=1 origin "$UPSTREAM_REF"
  git -C "$SOURCES_DIR" switch --detach --force FETCH_HEAD
  echo "upstream: $(git -C "$SOURCES_DIR" rev-parse HEAD)"
}

prepare_sources
if [[ "$PREPARE_ONLY" == true ]]; then
  exit 0
fi

for command in ast-grep jq cargo; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

PATCH_SPECS="
patches/permission-allow-all.yml crates/codegen/xai-grok-shell/src/session/acp_session_impl/spawn.rs
patches/folder-trust-inert.yml crates/codegen/xai-grok-workspace/src/folder_trust.rs
patches/release-repository.yml crates/codegen/xai-grok-update/src/version.rs
patches/reinstall-hint.yml crates/codegen/xai-grok-update/src/auto_update.rs
patches/release-installer.yml crates/codegen/xai-grok-update/src/auto_update.rs
"

assert_patch_seams() {
  echo "$PATCH_SPECS" | while read -r rule source; do
    [[ -n "$rule" ]] || continue
    count="$(ast-grep scan --rule "$ROOT_DIR/$rule" --info --json=compact "$SOURCES_DIR/$source" | jq 'length')"
    if [[ "$count" != "1" ]]; then
      echo "AST seam $rule expected exactly 1 match in $source, found $count" >&2
      exit 1
    fi
    echo "ok: $rule -> $source"
  done
}

assert_patch_seams
if [[ "$CHECK_ONLY" == true ]]; then
  exit 0
fi

if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "A stable X.Y.Z version is required for updater-compatible builds." >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "This distribution only builds for macOS arm64." >&2
  exit 1
fi

PATCHED_FILES="$(echo "$PATCH_SPECS" | awk 'NF && !seen[$2]++ { print $2 }')"
for source in $PATCHED_FILES; do
  if ! git -C "$SOURCES_DIR" diff --quiet HEAD -- "$source"; then
    echo "Refusing to patch a modified source file: $source" >&2
    exit 1
  fi
done

restore_sources() {
  # These paths were verified clean above; only undo this build's temporary rewrites.
  git -C "$SOURCES_DIR" restore --source=HEAD -- $PATCHED_FILES
}
trap restore_sources EXIT INT TERM

echo "$PATCH_SPECS" | while read -r rule source; do
  [[ -n "$rule" ]] || continue
  ast-grep scan --rule "$ROOT_DIR/$rule" --info --update-all "$SOURCES_DIR/$source"
done

(
  cd "$SOURCES_DIR"
  cargo fmt -p xai-grok-shell -p xai-grok-workspace -p xai-grok-update -- --check
  # Upstream enables release incremental artifacts; disabling them keeps the
  # build and cache inside GitHub's hosted-runner disk boundary.
  CARGO_INCREMENTAL=0 GROK_VERSION="$VERSION" cargo build --release -p xai-grok-pager-bin
)

mkdir -p "$OUTPUT_DIR"
artifact="$OUTPUT_DIR/grok-$VERSION-macos-aarch64"
install -m 755 "$SOURCES_DIR/target/release/xai-grok-pager" "$artifact"
# Ad-hoc signing keeps the CLI inside macOS's normal safety boundary without
# weakening Gatekeeper or requiring a private signing identity.
codesign --force --sign - "$artifact"

if [[ "$INSTALL" == true ]]; then
  grok_home="${GROK_HOME:-${HOME:?HOME is required}/.grok}"
  mkdir -p "$grok_home/downloads" "$grok_home/bin"
  installed="$grok_home/downloads/$(basename "$artifact")"
  install -m 755 "$artifact" "$installed"
  ln -sfn "../downloads/$(basename "$artifact")" "$grok_home/bin/grok"
  ln -sfn "../downloads/$(basename "$artifact")" "$grok_home/bin/agent"
  ln -sfn "$(basename "$artifact")" "$grok_home/downloads/grok-latest"
  echo "installed: $grok_home/bin/grok"
fi

echo "built: $artifact"
