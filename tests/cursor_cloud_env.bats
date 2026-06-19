#!/usr/bin/env bats
# Tests for the behaviors documented in AGENTS.md "Cursor Cloud specific instructions"
# Covers: dev wrapper invocation, commit-signing workaround, and no-remote smoke test.

load test_helper

setup() {
  # Use an isolated global git config so tests don't depend on the host environment
  export GIT_CONFIG_GLOBAL="$BATS_TMPDIR/cursor-cloud-global-$$"
  # Apply the documented fix: disable commit signing before running any git commands
  git config --global commit.gpgsign false
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  rm -f "$GIT_CONFIG_GLOBAL"
  teardown_integration_repo
}

# ── Dev wrapper (./bin/gtr) ──────────────────────────────────────────────────

@test "bin/gtr exists" {
  [ -f "$PROJECT_ROOT/bin/gtr" ]
}

@test "bin/gtr is executable" {
  [ -x "$PROJECT_ROOT/bin/gtr" ]
}

@test "bin/git-gtr exists alongside bin/gtr" {
  [ -f "$PROJECT_ROOT/bin/git-gtr" ]
}

@test "bin/git-gtr is executable" {
  [ -x "$PROJECT_ROOT/bin/git-gtr" ]
}

@test "bin/gtr delegates to bin/git-gtr (help exits 0)" {
  run "$PROJECT_ROOT/bin/gtr" --help
  [ "$status" -eq 0 ]
}

# ── Commit-signing workaround ────────────────────────────────────────────────
# AGENTS.md: "commit.gpgsign=true … blocks indefinitely. Before running tests,
# run: git config --global commit.gpgsign false"
# We do NOT test the gpgsign=true path because it hangs the test runner.

@test "git commit succeeds when commit.gpgsign=false in global config" {
  git config --global commit.gpgsign false
  run git -C "$TEST_REPO" commit --allow-empty -m "signing-off test"
  [ "$status" -eq 0 ]
}

@test "git commit succeeds when commit.gpgsign=false is set at repo level" {
  # Repo-level config overrides global, providing the same protection
  git -C "$TEST_REPO" config commit.gpgsign false
  run git -C "$TEST_REPO" commit --allow-empty -m "repo-level signing off"
  [ "$status" -eq 0 ]
}

@test "setup_integration_repo initial commit is reachable when gpgsign=false" {
  # The initial commit made by setup_integration_repo must be accessible;
  # if signing had blocked it the repo would have no HEAD.
  run git -C "$TEST_REPO" rev-parse HEAD
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "multiple commits succeed in sequence when gpgsign=false" {
  git config --global commit.gpgsign false
  git -C "$TEST_REPO" commit --allow-empty -m "second commit" --quiet
  run git -C "$TEST_REPO" commit --allow-empty -m "third commit"
  [ "$status" -eq 0 ]
}

# ── No-remote smoke test ─────────────────────────────────────────────────────
# AGENTS.md: "End-to-end smoke test in a disposable repo without a remote must
# use a local base, e.g. ./bin/gtr new <branch> --from-current --no-fetch"

@test "gtr new --from-current --no-fetch succeeds in a repo with no remote" {
  # Confirm there really is no remote in the integration repo
  run git -C "$TEST_REPO" remote
  [ "$output" = "" ]

  run cmd_create cloud-smoke-branch --from-current --no-fetch --yes
  [ "$status" -eq 0 ]
}

@test "gtr new --from-current --no-fetch creates the worktree directory" {
  cmd_create cursor-wt --from-current --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/cursor-wt" ]
}

@test "gtr new without --from or --from-current fails in a repo with no remote" {
  # Documents why a local base is required: the default base is origin/<default-branch>
  # which cannot be resolved when there is no 'origin' remote.
  run cmd_create needs-remote --no-fetch --yes
  [ "$status" -ne 0 ]
}

@test "gtr new --from-current creates worktree at HEAD of current branch" {
  local expected_sha
  expected_sha=$(git -C "$TEST_REPO" rev-parse HEAD)

  cmd_create head-check --from-current --no-fetch --yes

  local actual_sha
  actual_sha=$(git -C "$TEST_WORKTREES_DIR/head-check" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

# ── Dev tooling availability ─────────────────────────────────────────────────
# AGENTS.md: "Dev tooling is just bats (tests) and shellcheck (lint)"

@test "bats is available in PATH" {
  run which bats
  [ "$status" -eq 0 ]
}

@test "shellcheck is available in PATH" {
  run which shellcheck
  [ "$status" -eq 0 ]
}

@test "shellcheck passes on bin/gtr" {
  run shellcheck "$PROJECT_ROOT/bin/gtr"
  [ "$status" -eq 0 ]
}

@test "shellcheck passes on bin/git-gtr" {
  run shellcheck "$PROJECT_ROOT/bin/git-gtr"
  [ "$status" -eq 0 ]
}
