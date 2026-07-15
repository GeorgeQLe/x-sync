#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XSYNC="$(cd "$SCRIPT_DIR/.." && pwd)/x-sync.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

git_quiet() {
  git "$@" >/dev/null
}

configure_repo() {
  local repo="$1"
  git_quiet -C "$repo" config user.name "x-sync regression"
  git_quiet -C "$repo" config user.email "x-sync@example.invalid"
}

assert_contains() {
  local output="$1"
  local expected="$2"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\n\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}

create_remote() {
  local case_root="$1"
  mkdir -p "$case_root/infra" "$case_root/scan" "$case_root/home"
  git_quiet init --bare --initial-branch=master "$case_root/infra/origin.git"
  git_quiet init --initial-branch=master "$case_root/infra/seed"
  configure_repo "$case_root/infra/seed"
  printf 'initial\n' >"$case_root/infra/seed/shared.txt"
  git_quiet -C "$case_root/infra/seed" add shared.txt
  git_quiet -C "$case_root/infra/seed" commit -m "initial"
  git_quiet -C "$case_root/infra/seed" remote add origin "$case_root/infra/origin.git"
  git_quiet -C "$case_root/infra/seed" push -u origin master
}

test_conflict_word_is_success() {
  local case_root="$TEST_ROOT/conflict-word"
  local output status
  create_remote "$case_root"
  git_quiet clone "$case_root/infra/origin.git" "$case_root/scan/client"
  printf 'harmless\n' >"$case_root/infra/seed/conflict-notes.txt"
  git_quiet -C "$case_root/infra/seed" add conflict-notes.txt
  git_quiet -C "$case_root/infra/seed" commit -m "document conflict handling"
  git_quiet -C "$case_root/infra/seed" push

  status=0
  output=$(cd "$case_root/scan" && HOME="$case_root/home" "$XSYNC" 2>&1) || status=$?
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; exit 1; }
  assert_contains "$output" "Success:   1"
  assert_contains "$output" "Conflicts: 0"
  assert_contains "$output" "Failures:  0"
}

test_real_conflict() {
  local case_root="$TEST_ROOT/real-conflict"
  local output status
  create_remote "$case_root"
  git_quiet clone "$case_root/infra/origin.git" "$case_root/scan/client"
  configure_repo "$case_root/scan/client"
  git_quiet -C "$case_root/scan/client" config pull.rebase false
  printf 'local\n' >"$case_root/scan/client/shared.txt"
  git_quiet -C "$case_root/scan/client" commit -am "local change"
  printf 'remote\n' >"$case_root/infra/seed/shared.txt"
  git_quiet -C "$case_root/infra/seed" commit -am "remote change"
  git_quiet -C "$case_root/infra/seed" push

  status=0
  output=$(cd "$case_root/scan" && HOME="$case_root/home" "$XSYNC" 2>&1) || status=$?
  [ "$status" -eq 1 ] || { printf 'Expected exit 1, got %d\n%s\n' "$status" "$output" >&2; exit 1; }
  assert_contains "$output" "Conflicts: 1"
  assert_contains "$output" "Failures:  0"
}

test_divergence_is_failure() {
  local case_root="$TEST_ROOT/divergence"
  local output status
  create_remote "$case_root"
  git_quiet clone "$case_root/infra/origin.git" "$case_root/scan/client"
  configure_repo "$case_root/scan/client"
  printf 'local\n' >"$case_root/scan/client/local.txt"
  git_quiet -C "$case_root/scan/client" add local.txt
  git_quiet -C "$case_root/scan/client" commit -m "local change"
  printf 'remote\n' >"$case_root/infra/seed/remote.txt"
  git_quiet -C "$case_root/infra/seed" add remote.txt
  git_quiet -C "$case_root/infra/seed" commit -m "remote change"
  git_quiet -C "$case_root/infra/seed" push

  status=0
  output=$(cd "$case_root/scan" && HOME="$case_root/home" "$XSYNC" 2>&1) || status=$?
  [ "$status" -eq 1 ] || { printf 'Expected exit 1, got %d\n%s\n' "$status" "$output" >&2; exit 1; }
  assert_contains "$output" "Conflicts: 0"
  assert_contains "$output" "Failures:  1"
}

test_conflict_word_is_success
test_real_conflict
test_divergence_is_failure
printf 'x-sync regression tests passed\n'
