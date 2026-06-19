#!/usr/bin/env bats
# Tests for behaviors documented in the "Cursor Cloud specific instructions"
# section of AGENTS.md, added in the Cursor Cloud setup PR.
#
# Covers:
#   - ./bin/gtr dev wrapper is executable and invocable
#   - commit.gpgsign=true blocks git commit; disabling it restores normal operation
#   - gtr new --from-current --no-fetch succeeds in a repo with no origin remote
#   - gtr new without --no-fetch fails when no origin remote exists
#   - --from-current resolves to the current branch (not requiring a remote)

load test_helper

# ── bin/gtr dev wrapper ──────────────────────────────────────────────────────

@test "bin/gtr dev wrapper exists and is executable" {
  [ -x "$PROJECT_ROOT/bin/gtr" ]
}

@test "bin/gtr dev wrapper delegates to bin/git-gtr (version output)" {
  run "$PROJECT_ROOT/bin/gtr" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr version"* ]]
}

@test "bin/git-gtr is executable" {
  [ -x "$PROJECT_ROOT/bin/git-gtr" ]
}

# ── commit.gpgsign workaround ────────────────────────────────────────────────
# AGENTS.md notes that commit.gpgsign=true hangs integration tests because the
# signing helper blocks indefinitely.  The documented fix is:
#   git config --global commit.gpgsign false
# These tests verify the observable effect of that config knob.

@test "git commit succeeds when commit.gpgsign is false" {
  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" config commit.gpgsign false

  run git -C "$TEST_REPO" commit --allow-empty -m "test commit" --quiet
  rm -rf "$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "git commit fails when commit.gpgsign is true and no signing key exists" {
  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" config commit.gpgsign true
  git -C "$TEST_REPO" config gpg.format ssh
  git -C "$TEST_REPO" config user.signingkey "nonexistent-key"

  run git -C "$TEST_REPO" commit --allow-empty -m "should fail" --quiet 2>/dev/null
  rm -rf "$TEST_REPO"
  [ "$status" -ne 0 ]
}

@test "disabling gpgsign via local config overrides a true global value" {
  local orig_global_gpgsign
  orig_global_gpgsign=$(git config --global --get commit.gpgsign 2>/dev/null || echo "unset")

  # Temporarily set global gpgsign to true
  git config --global commit.gpgsign true

  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  # Apply the documented workaround at the local level
  git -C "$TEST_REPO" config commit.gpgsign false

  run git -C "$TEST_REPO" commit --allow-empty -m "workaround test" --quiet
  local commit_status="$status"

  # Restore global state
  if [ "$orig_global_gpgsign" = "unset" ]; then
    git config --global --unset commit.gpgsign 2>/dev/null || true
  else
    git config --global commit.gpgsign "$orig_global_gpgsign"
  fi
  rm -rf "$TEST_REPO"

  [ "$commit_status" -eq 0 ]
}

# ── --no-fetch required when no origin remote ────────────────────────────────
# AGENTS.md states: "End-to-end smoke test in a disposable repo without a
# remote must use a local base, e.g. ./bin/gtr new <branch> --from-current
# --no-fetch.  The default base is origin/<default-branch>, which fails when
# there is no origin remote."

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

@test "cmd_create with --from-current --no-fetch succeeds without an origin remote" {
  # Confirm there is no origin remote in the disposable repo
  run git remote get-url origin
  [ "$status" -ne 0 ]

  # The smoke-test pattern from AGENTS.md
  run cmd_create smoke-test-branch --from-current --no-fetch --yes
  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/smoke-test-branch" ]
}

@test "cmd_create without --no-fetch exits non-zero when no origin remote exists" {
  # Confirm there is no origin remote
  run git remote get-url origin
  [ "$status" -ne 0 ]

  # Without --no-fetch, gtr tries to fetch origin/<default-branch>, which fails
  run cmd_create no-fetch-fail-branch --yes
  [ "$status" -ne 0 ]
}

@test "cmd_create --from-current uses current branch as base (not remote)" {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  # Create a second commit so we can verify which ref was used
  git commit --allow-empty -m "second commit" --quiet

  run cmd_create from-current-test --from-current --no-fetch --yes
  [ "$status" -eq 0 ]

  # The new worktree should be on a new branch rooted at the current HEAD
  local wt_path="$TEST_WORKTREES_DIR/from-current-test"
  [ -d "$wt_path" ]

  local wt_head main_head
  wt_head=$(git -C "$wt_path" rev-parse HEAD)
  main_head=$(git -C "$TEST_REPO" rev-parse HEAD)
  [ "$wt_head" = "$main_head" ]
}

@test "cmd_create --from-current --no-fetch with slashed branch name sanitizes folder" {
  run cmd_create feature/cursor-cloud --from-current --no-fetch --yes
  [ "$status" -eq 0 ]
  # Slashes in the branch name must be replaced with hyphens in the directory name
  [ -d "$TEST_WORKTREES_DIR/feature-cursor-cloud" ]
}
