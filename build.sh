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

for command in ast-grep jq cargo rustfmt; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

REQUIRED_PATCH_SPECS="
patches/permission-allow-all.yml crates/codegen/xai-grok-shell/src/session/acp_session_impl/spawn.rs
patches/folder-trust-inert.yml crates/codegen/xai-grok-workspace/src/folder_trust.rs
patches/release-repository.yml crates/codegen/xai-grok-update/src/version.rs
patches/reinstall-hint.yml crates/codegen/xai-grok-update/src/auto_update.rs
patches/release-installer.yml crates/codegen/xai-grok-update/src/auto_update.rs
patches/runtime/deleted-cwd/regression.yml crates/codegen/xai-grok-tools/src/computer/local/terminal.rs
patches/runtime/bash-workdir-tilde/regression.yml crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs
"

RUNTIME_CWD_PATCH="patches/runtime/deleted-cwd/recover.yml"
RUNTIME_CWD_SATISFIED="patches/runtime/deleted-cwd/satisfied.yml"
RUNTIME_CWD_SOURCE="crates/codegen/xai-grok-tools/src/computer/local/terminal.rs"
RUNTIME_TILDE_PATCH="patches/runtime/bash-workdir-tilde/expand.yml"
RUNTIME_TILDE_SATISFIED="patches/runtime/bash-workdir-tilde/satisfied.yml"
RUNTIME_TILDE_SOURCE="crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs"
ACTIVE_PATCH_SPECS="$REQUIRED_PATCH_SPECS"

assert_patch_seams() {
  echo "$REQUIRED_PATCH_SPECS" | while read -r rule source; do
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

# Conditional patches have a three-state contract: apply to the known buggy
# seam, skip only when a recognized equivalent fix already exists, and fail on
# unknown drift so an upstream refactor cannot silently reintroduce the bug.
apply_conditional_patch() {
  # Three-state contract: skip only on a recognized equivalent upstream fix,
  # apply to the known buggy seam, fail on unknown drift.
  local name="$1" patch="$2" satisfied="$3" source="$4"
  local satisfied_count apply_count
  satisfied_count="$(ast-grep scan --rule "$ROOT_DIR/$satisfied" --info --json=compact "$SOURCES_DIR/$source" | jq 'length')"
  apply_count="$(ast-grep scan --rule "$ROOT_DIR/$patch" --info --json=compact "$SOURCES_DIR/$source" | jq 'length')"
  if [[ "$satisfied_count" == "1" ]]; then
    echo "skip: upstream already satisfies $name"
  elif [[ "$satisfied_count" == "0" && "$apply_count" == "1" ]]; then
    ACTIVE_PATCH_SPECS+="$patch $source"$'\n'
    echo "apply: $patch -> $source"
  else
    echo "$name patch contract drifted: apply=$apply_count satisfied=$satisfied_count" >&2
    exit 1
  fi
}

apply_conditional_patch "Deleted-cwd" "$RUNTIME_CWD_PATCH" "$RUNTIME_CWD_SATISFIED" "$RUNTIME_CWD_SOURCE"
apply_conditional_patch "Bash workdir tilde" "$RUNTIME_TILDE_PATCH" "$RUNTIME_TILDE_SATISFIED" "$RUNTIME_TILDE_SOURCE"

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

PATCHED_FILES="$(echo "$ACTIVE_PATCH_SPECS" | awk 'NF && !seen[$2]++ { print $2 }')"
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

echo "$ACTIVE_PATCH_SPECS" | while read -r rule source; do
  [[ -n "$rule" ]] || continue
  ast-grep scan --rule "$ROOT_DIR/$rule" --info --update-all "$SOURCES_DIR/$source"
done

assert_postcondition() {
  local name="$1" satisfied="$2" source="$3"
  local count
  count="$(ast-grep scan --rule "$ROOT_DIR/$satisfied" --info --json=compact "$SOURCES_DIR/$source" | jq 'length')"
  if [[ "$count" != "1" ]]; then
    echo "$name postcondition expected 1 match, found $count" >&2
    exit 1
  fi
}

assert_postcondition "Deleted-cwd recovery" "$RUNTIME_CWD_SATISFIED" "$RUNTIME_CWD_SOURCE"
assert_postcondition "Bash workdir tilde expansion" "$RUNTIME_TILDE_SATISFIED" "$RUNTIME_TILDE_SOURCE"

(
  cd "$SOURCES_DIR"
  cargo fmt -p xai-grok-shell -p xai-grok-workspace -p xai-grok-update -- --check
  # ast-grep preserves metavariable indentation when it inserts the regression
  # test; format only the owned patched files so unrelated upstream files stay untouched.
  rustfmt --edition 2024 \
    crates/codegen/xai-grok-tools/src/computer/local/terminal.rs \
    crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs
  cargo test --release -p xai-grok-tools test_persistent_shell_recovers_deleted_cwd --lib
  cargo test --release -p xai-grok-tools workdir_expands_tilde_to_home --lib
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
