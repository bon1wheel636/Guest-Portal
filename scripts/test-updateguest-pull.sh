#!/usr/bin/env bash
# Exercises updateguest's fast-forward recovery without a root container.
# Usage: bash scripts/test-updateguest-pull.sh

set -euo pipefail

ROOT=""
PASSED=0
FAILED=0

pass() {
  echo "PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "FAIL: $1"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    pass "$desc"
  else
    fail "$desc (missing $path)"
  fi
}

assert_file_absent() {
  local desc="$1"
  local path="$2"
  if [[ ! -e "$path" ]]; then
    pass "$desc"
  else
    fail "$desc (still present: $path)"
  fi
}

cleanup() {
  if [[ -n "$ROOT" && -d "$ROOT" ]]; then
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${WORKSPACE}/scripts/updateguest.sh"

run_as_app_user() {
  bash -c "$1"
}

init_origin() {
  local origin="$1"
  local seed="$2"
  git init -q -b main "$seed"
  git -C "$seed" config user.email "updateguest-test@example.com"
  git -C "$seed" config user.name "updateguest test"
  mkdir -p "$seed/scripts"
  printf 'lock-v1\n' > "$seed/package-lock.json"
  printf 'echo v1\n' > "$seed/scripts/updateguest.sh"
  printf 'readme-v1\n' > "$seed/README.md"
  printf 'uploads/\n' > "$seed/.gitignore"
  git -C "$seed" add package-lock.json scripts/updateguest.sh README.md .gitignore
  git -C "$seed" commit -q -m 'v1'
  git init --bare -q -b main "$origin"
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push -q -u origin main
}

clone_app() {
  local origin="$1"
  local app="$2"
  git clone -q "$origin" "$app"
  git -C "$app" config user.email "updateguest-test@example.com"
  git -C "$app" config user.name "updateguest test"
}

commit_and_push() {
  local seed="$1"
  local message="$2"
  git -C "$seed" add -A
  git -C "$seed" commit -q -m "$message"
  git -C "$seed" push -q origin main
}

run_pull() {
  local app="$1"
  APP_PATH="$app"
  DRY_RUN=false
  set +e
  (
    pull_latest_code
  )
  local status=$?
  set -e
  return "$status"
}

test_lockfile_and_installer_drift() {
  local origin="$ROOT/origin-lock.git"
  local seed="$ROOT/seed-lock"
  local app="$ROOT/app-lock"
  init_origin "$origin" "$seed"
  clone_app "$origin" "$app"

  printf 'lock-rewritten-by-npm\n' > "$app/package-lock.json"
  printf 'echo local-bootstrap\n' > "$app/scripts/updateguest.sh"
  mkdir -p "$app/uploads/stay"
  printf 'photo\n' > "$app/uploads/stay/a.jpg"
  printf 'operator note\n' > "$app/notes.txt"

  printf 'lock-v2\n' > "$seed/package-lock.json"
  printf 'echo v2\n' > "$seed/scripts/updateguest.sh"
  printf 'server-v2\n' > "$seed/server.js"
  commit_and_push "$seed" 'v2'

  local output
  output="$(run_pull "$app" 2>&1)" || {
    fail "lockfile drift pull failed: ${output}"
    return
  }
  assert_eq "pull discards rewritten package-lock.json" "lock-v2" "$(cat "$app/package-lock.json")"
  assert_eq "pull discards local installer script" "echo v2" "$(cat "$app/scripts/updateguest.sh")"
  assert_file_exists "pull fast-forwards new tracked file" "$app/server.js"
  assert_file_exists "pull keeps guest uploads" "$app/uploads/stay/a.jpg"
  assert_file_exists "successful pull keeps unrelated untracked files" "$app/notes.txt"
  if [[ "$output" == *"Discarding local changes to package-lock.json"* ]]; then
    pass "pull logs package-lock.json restore"
  else
    fail "pull logs package-lock.json restore (output: ${output})"
  fi

  printf 'lock-after-npm-install\n' > "$app/package-lock.json"
  APP_PATH="$app"
  restore_generated_lockfile
  assert_eq "post-install lockfile is restored to HEAD" "lock-v2" "$(cat "$app/package-lock.json")"
}

test_other_tracked_drift_retries() {
  local origin="$ROOT/origin-readme.git"
  local seed="$ROOT/seed-readme"
  local app="$ROOT/app-readme"
  init_origin "$origin" "$seed"
  clone_app "$origin" "$app"

  printf 'readme-local\n' > "$app/README.md"
  mkdir -p "$app/uploads"
  printf 'photo\n' > "$app/uploads/keep.jpg"
  printf 'readme-v2\n' > "$seed/README.md"
  printf 'added\n' > "$seed/extra.txt"
  commit_and_push "$seed" 'readme v2'

  local output
  output="$(run_pull "$app" 2>&1)" || {
    fail "tracked drift retry failed: ${output}"
    return
  }
  assert_eq "retry restores README.md from upstream" "readme-v2" "$(cat "$app/README.md")"
  assert_file_exists "retry fast-forwards" "$app/extra.txt"
  assert_file_exists "retry keeps uploads" "$app/uploads/keep.jpg"
  if [[ "$output" == *"Restoring tracked files and retrying"* ]]; then
    pass "retry explains why the second pull ran"
  else
    fail "retry explains why the second pull ran (output: ${output})"
  fi
}

test_untracked_collision_is_removed() {
  local origin="$ROOT/origin-untracked.git"
  local seed="$ROOT/seed-untracked"
  local app="$ROOT/app-untracked"
  init_origin "$origin" "$seed"
  clone_app "$origin" "$app"

  printf 'local untracked\n' > "$app/server.js"
  mkdir -p "$app/uploads"
  printf 'photo\n' > "$app/uploads/keep.jpg"
  printf 'server-upstream\n' > "$seed/server.js"
  commit_and_push "$seed" 'add server.js'

  local output
  output="$(run_pull "$app" 2>&1)" || {
    fail "untracked collision pull failed: ${output}"
    return
  }
  assert_eq "upstream replaces colliding untracked file" "server-upstream" "$(cat "$app/server.js")"
  assert_file_exists "clean keeps uploads" "$app/uploads/keep.jpg"
}

test_diverged_history_is_not_reset() {
  local origin="$ROOT/origin-diverge.git"
  local seed="$ROOT/seed-diverge"
  local app="$ROOT/app-diverge"
  init_origin "$origin" "$seed"
  clone_app "$origin" "$app"

  printf 'local commit\n' > "$app/LOCAL.txt"
  git -C "$app" add LOCAL.txt
  git -C "$app" commit -q -m 'local'
  local head_before
  head_before="$(git -C "$app" rev-parse HEAD)"

  printf 'upstream\n' > "$seed/UPSTREAM.txt"
  commit_and_push "$seed" 'upstream diverge'

  local output status
  set +e
  output="$(run_pull "$app" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    pass "diverged checkout fails the pull"
  else
    fail "diverged checkout fails the pull (status 0)"
  fi
  assert_eq "diverged checkout stays on the local commit" "$head_before" "$(git -C "$app" rev-parse HEAD)"
  assert_file_exists "local commit is kept" "$app/LOCAL.txt"
  assert_file_absent "upstream commit is not reset onto" "$app/UPSTREAM.txt"
  if [[ "$output" == *"git pull failed"* ]]; then
    pass "diverged pull reports an error"
  else
    fail "diverged pull reports an error (output: ${output})"
  fi
}

test_dry_run_leaves_lockfile() {
  local origin="$ROOT/origin-dry.git"
  local seed="$ROOT/seed-dry"
  local app="$ROOT/app-dry"
  init_origin "$origin" "$seed"
  clone_app "$origin" "$app"
  printf 'dirty-lock\n' > "$app/package-lock.json"
  APP_PATH="$app"
  DRY_RUN=true
  pull_latest_code >/dev/null
  assert_eq "dry run does not discard package-lock.json" "dirty-lock" "$(cat "$app/package-lock.json")"
}

main() {
  ROOT="$(mktemp -d /tmp/gp-updateguest-pull.XXXXXX)"
  echo "Running updateguest pull tests in ${ROOT}"
  echo ""
  test_lockfile_and_installer_drift
  test_other_tracked_drift_retries
  test_untracked_collision_is_removed
  test_diverged_history_is_not_reset
  test_dry_run_leaves_lockfile
  echo ""
  echo "Results: ${PASSED} passed, ${FAILED} failed"
  if [[ "$FAILED" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
