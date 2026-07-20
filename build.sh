#!/usr/bin/env bash
set -euo pipefail

# Upstream sets `incremental = true` on [profile.release], which makes every
# release-profile cargo invocation here (tests included, not just the final
# build) write into target/release/incremental — measured at 8.3 GB locally.
# Nothing reuses those artifacts: each CI run starts from a restored cache that
# never contained them. Export once so no invocation can miss it.
export CARGO_INCREMENTAL=0

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

  # CI runs --prepare (to populate Cargo.lock for the cache key) and then the
  # real build, so an exact-SHA ref would otherwise be fetched twice. The tree
  # was just verified clean above, so an already-checked-out SHA needs no work.
  if [[ "$(git -C "$SOURCES_DIR" rev-parse --verify --quiet HEAD || true)" == "$UPSTREAM_REF" ]]; then
    echo "upstream: $UPSTREAM_REF (already checked out)"
    return
  fi

  git -C "$SOURCES_DIR" fetch --depth=1 origin "$UPSTREAM_REF"
  git -C "$SOURCES_DIR" switch --detach --force FETCH_HEAD
  echo "upstream: $(git -C "$SOURCES_DIR" rev-parse HEAD)"
}

prepare_sources
if [[ "$PREPARE_ONLY" == true ]]; then
  exit 0
fi

for command in ast-grep jq cargo rustfmt python3; do
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
patches/otty-kkp.yml crates/codegen/xai-grok-pager-render/src/terminal/mod.rs
patches/otty-kkp-test-capability.yml crates/codegen/xai-grok-pager-render/src/terminal/test.rs
patches/otty-kkp-test-skip-reason.yml crates/codegen/xai-grok-pager-render/src/terminal/test.rs
patches/otty-kkp-test-focus-tracking.yml crates/codegen/xai-grok-pager/src/diagnostics.rs
patches/runtime/deleted-cwd/regression.yml crates/codegen/xai-grok-tools/src/computer/local/terminal.rs
patches/runtime/bash-workdir-tilde/regression.yml crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs
patches/runtime/prompt-background-tasks/regression.yml crates/codegen/xai-grok-agent/src/prompt/template.rs
patches/runtime/skill-id-base/skill-info-methods.yml crates/codegen/xai-grok-tools/src/implementations/skills/types.rs
patches/runtime/skill-id-tool/description.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/input-id.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/result-collision.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/find-by-id.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/run-match.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/list-files-relative.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/format-output.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-format-name-import.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/tests.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-find-short.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-find-qualified.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-find-ambiguous.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-find-qualified-ambiguous.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-skill-ambiguous.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-skill-notfound.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-skill-empty.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-test-import-testctx.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-test-import-resources.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-test-import-tempdir.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_loads_content_from_file.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_body_reaches_prompt_format.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_lists_bundled_files.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_file_not_found_returns_error.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-works_through_erased_interface.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-frontmatter_stripping.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_message_xml_structure.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-base_directory_in_output.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-skill_with_no_bundled_files.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-empty_skill_content.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/remove-old-input-test-ten_file_cap.yml crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs
patches/runtime/skill-id-tool/register-default.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-plan.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-concise.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-hashline.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-codex.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-explore.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-plan-readonly.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-orchestrator.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-plan-no-subagents.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-ask-user.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-tool/register-grok-computer.yml crates/codegen/xai-grok-agent/src/config.rs
patches/runtime/skill-id-listing/header.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/entry-struct.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/build-entry.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/format.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/name-only.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/overhead.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/regression.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/test-entry-overhead.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/test-entry-xml-overhead.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-id-listing/remove-old-entry-test.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-fuzzy-dedup/agent-dedup.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/tracker-dedup.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/mod.rs
patches/runtime/skill-fuzzy-dedup/announcement-id.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs
patches/runtime/skill-fuzzy-dedup/conditional-pending.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/conditional.rs
patches/runtime/skill-fuzzy-dedup/conditional-activate.yml crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/conditional.rs
patches/runtime/skill-fuzzy-dedup/persisted-field.yml crates/codegen/xai-grok-shell/src/session/announcement_state.rs
patches/runtime/skill-fuzzy-dedup/persist-write.yml crates/codegen/xai-grok-shell/src/session/acp_session_impl/mcp.rs
patches/runtime/skill-fuzzy-dedup/persist-read.yml crates/codegen/xai-grok-shell/src/session/acp_session_impl/spawn.rs
patches/runtime/skill-fuzzy-dedup/remove-rekey-helper.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-hashmap-import.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-name-validator-import.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/announcement-tests-roundtrip.yml crates/codegen/xai-grok-shell/src/session/announcement_state.rs
patches/runtime/skill-fuzzy-dedup/announcement-tests-clean-break.yml crates/codegen/xai-grok-shell/src/session/announcement_state.rs
patches/runtime/skill-fuzzy-dedup/remove-test-list_skills_auto_and_config_overlap_keeps_config_toml_source.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_skills_name_collision_does_not_propagate_config_source.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-user_skills_shadow_bundled_skills.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-skills_shadow_commands_with_same_name.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_rekeys_same_scope_name_collision_to_dir_basename.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_hands_name_back_to_basename_owner.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_rekeys_every_same_scope_claimant.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_challenger_without_basename_claim_is_still_shadowed.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_rekeyed_name_shadows_lower_scope_claimant.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_same_scope_cross_harness_loser_resurfaces.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_frontmatter_owner_evicts_rekeyed_squatter.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_cross_scope_shadowing_unchanged.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-dedupe_same_scope_same_basename_still_drops.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-test-copied_skill_dir_with_stale_frontmatter_name_surfaces_both.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-1.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-2.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-3.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-4.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-5.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-6.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-7.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
patches/runtime/skill-fuzzy-dedup/remove-doc-rekey.yml crates/codegen/xai-grok-agent/src/prompt/skills.rs
"

RUNTIME_CWD_PATCH="patches/runtime/deleted-cwd/recover.yml"
RUNTIME_CWD_SATISFIED="patches/runtime/deleted-cwd/satisfied.yml"
RUNTIME_CWD_SOURCE="crates/codegen/xai-grok-tools/src/computer/local/terminal.rs"
RUNTIME_TILDE_PATCH="patches/runtime/bash-workdir-tilde/expand.yml"
RUNTIME_TILDE_SATISFIED="patches/runtime/bash-workdir-tilde/satisfied.yml"
RUNTIME_TILDE_SOURCE="crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs"
RUNTIME_PROMPT_DIR="patches/runtime/prompt-background-tasks"
RUNTIME_PROMPT_SOURCE="crates/codegen/xai-grok-agent/templates/prompt.md"
RUNTIME_PROMPT_ENCRYPTED="crates/codegen/xai-grok-agent/src/prompt/prompt_encrypted.rs"
APPLY_PROMPT_TEXT_PATCH=false
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

text_count() {
  python3 - "$1" "$2" <<'PY'
import sys

needle = open(sys.argv[1], encoding="utf-8").read()
haystack = open(sys.argv[2], encoding="utf-8").read()
print(haystack.count(needle))
PY
}

# Text patches carry the same three-state contract as AST patches, for files
# ast-grep cannot parse (jinja templates, prose).
satisfied_count="$(text_count "$ROOT_DIR/$RUNTIME_PROMPT_DIR/satisfied.md" "$SOURCES_DIR/$RUNTIME_PROMPT_SOURCE")"
apply_count="$(text_count "$ROOT_DIR/$RUNTIME_PROMPT_DIR/section.old.md" "$SOURCES_DIR/$RUNTIME_PROMPT_SOURCE")"
if [[ "$satisfied_count" == "1" ]]; then
  echo "skip: upstream already satisfies Background-tasks prompt"
elif [[ "$satisfied_count" == "0" && "$apply_count" == "1" ]]; then
  APPLY_PROMPT_TEXT_PATCH=true
  echo "apply: $RUNTIME_PROMPT_DIR/section.new.md -> $RUNTIME_PROMPT_SOURCE"
else
  echo "Background-tasks prompt patch contract drifted: apply=$apply_count satisfied=$satisfied_count" >&2
  exit 1
fi

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

PATCHED_FILES="$(echo "$ACTIVE_PATCH_SPECS" | awk 'NF && !seen[$2]++ { print $2 }') $RUNTIME_PROMPT_SOURCE $RUNTIME_PROMPT_ENCRYPTED"
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

if [[ "$APPLY_PROMPT_TEXT_PATCH" == true ]]; then
  python3 - "$ROOT_DIR/$RUNTIME_PROMPT_DIR/section.old.md" "$ROOT_DIR/$RUNTIME_PROMPT_DIR/section.new.md" "$SOURCES_DIR/$RUNTIME_PROMPT_SOURCE" <<'PY'
import sys

old = open(sys.argv[1], encoding="utf-8").read()
new = open(sys.argv[2], encoding="utf-8").read()
path = sys.argv[3]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("prompt section old text must appear exactly once")
open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
PY
fi

# Templates ship XOR-encrypted in the binary; regenerate after any prompt
# change. Deterministic, so an unchanged template re-encrypts identically.
( cd "$SOURCES_DIR/crates/codegen/xai-grok-agent" && python3 scripts/encrypt_templates.py )

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

postcondition_text="$(text_count "$ROOT_DIR/$RUNTIME_PROMPT_DIR/satisfied.md" "$SOURCES_DIR/$RUNTIME_PROMPT_SOURCE")"
if [[ "$postcondition_text" != "1" ]]; then
  echo "Background-tasks prompt postcondition expected 1 match, found $postcondition_text" >&2
  exit 1
fi

(
  cd "$SOURCES_DIR"
  # ast-grep preserves metavariable indentation when it inserts the regression
  # test; format only the owned patched files so unrelated upstream files stay untouched.
  rustfmt --edition 2024 \
    crates/codegen/xai-grok-tools/src/computer/local/terminal.rs \
    crates/codegen/xai-grok-tools/src/implementations/opencode/bash/mod.rs \
    crates/codegen/xai-grok-tools/src/implementations/skills/types.rs \
    crates/codegen/xai-grok-tools/src/implementations/opencode/skill/mod.rs \
    crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/listing.rs \
    crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/mod.rs \
    crates/codegen/xai-grok-tools/src/types/skill_discovery_tracker/conditional.rs \
    crates/codegen/xai-grok-agent/src/config.rs \
    crates/codegen/xai-grok-agent/src/prompt/skills.rs \
    crates/codegen/xai-grok-shell/src/session/announcement_state.rs \
    crates/codegen/xai-grok-shell/src/session/acp_session_impl/mcp.rs \
    crates/codegen/xai-grok-shell/src/session/acp_session_impl/spawn.rs \
    crates/codegen/xai-grok-pager-render/src/terminal/mod.rs \
    crates/codegen/xai-grok-pager-render/src/terminal/test.rs \
    crates/codegen/xai-grok-pager/src/diagnostics.rs
  cargo fmt -p xai-grok-shell -p xai-grok-workspace -p xai-grok-update -- --check
  # One invocation per package: libtest ORs multiple positional filters, and
  # each extra `cargo test` re-fingerprints the whole 1274-crate graph before
  # deciding it has nothing to rebuild.
  cargo test --release -p xai-grok-tools --lib -- \
    test_persistent_shell_recovers_deleted_cwd \
    workdir_expands_tilde_to_home \
    fnv_vector_low_24_bits \
    find_skill_by_id_and_collision \
    skill_file_read_and_menu \
    markdown_listing_includes_ids_in_full_and_name_only_tiers
  cargo test --release -p xai-grok-agent --lib -- \
    dedupe_skills_name_collision_does_not_propagate_config_source \
    test_background_tasks_defines_callback_and_poll
  cargo test --release -p xai-grok-shell --lib -- backward_compat_empty_json
  # Otty KKP opt-in: the second test also pins the IME payload-origin gate that
  # must stay Otty-only. The diagnostics focus-tracking flip rides the same
  # predicate and is left to the seam assertion — its crate is too expensive to
  # build a test harness for on every release.
  cargo test --release -p xai-grok-pager-render --lib -- \
    otty_negotiates_kitty_keyboard \
    otty_is_capability_classified
  GROK_VERSION="$VERSION" cargo build --release -p xai-grok-pager-bin
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
