#!/usr/bin/env bash
set -euo pipefail

# x-sync: Recursively find git repos and pull from their remotes.
# Reports merge conflicts and failures at the end.

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

verbose() { [ "$VERBOSE" -eq 1 ] && printf "  [verbose] %s\n" "$1" || true; }

has_unmerged_entries() {
  local repo_dir="$1"
  [ -n "$(git -C "$repo_dir" ls-files -u)" ]
}

BASE_DIR="$(pwd)"
failures=()
conflicts=()
successes=()

# Spinner for long-running operations
spin_pid=""
start_spinner() {
  local msg="$1"
  printf "%s " "$msg"
  (
    chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    i=0
    while true; do
      printf "\r%s %s" "$msg" "${chars:i%${#chars}:1}"
      i=$((i + 1))
      sleep 0.1
    done
  ) &
  spin_pid=$!
}
stop_spinner() {
  if [ -n "$spin_pid" ]; then
    kill "$spin_pid" 2>/dev/null
    wait "$spin_pid" 2>/dev/null || true
    spin_pid=""
    printf "\r\033[K"
  fi
}
trap stop_spinner EXIT

# Discover repos
start_spinner "Scanning for git repos..."
mapfile -t git_dirs < <(find "$BASE_DIR" -type d -name ".git" | sort)
stop_spinner
printf "Found %d git repo(s). Syncing...\n" "${#git_dirs[@]}"

for gitdir in "${git_dirs[@]}"; do
  repo_dir="$(dirname "$gitdir")"
  rel_path="${repo_dir#"$BASE_DIR"/}"

  verbose "Found git repo at $repo_dir"
  printf "\n=== Pulling: %s ===\n" "$rel_path"

  verbose "Checking for remote tracking branch"
  if ! git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    verbose "No upstream tracking branch — skipping"
    successes+=("$rel_path")
    printf "  (no upstream tracking branch, skipped)\n"
    continue
  fi

  verbose "Running git pull"
  output=""
  if output=$(git -C "$repo_dir" pull 2>&1); then
    pull_status=0
  else
    pull_status=$?
  fi

  if has_unmerged_entries "$repo_dir"; then
    verbose "Unmerged index entries detected in $rel_path"
    conflicts+=("$rel_path")
    printf "  CONFLICT: %s\n" "$output"
  elif [ "$pull_status" -eq 0 ]; then
    verbose "Pull completed cleanly for $rel_path"
    successes+=("$rel_path")
    printf "  %s\n" "$output"
  else
    verbose "Pull command failed for $rel_path"
    verbose "Recording failure for $rel_path"
    failures+=("$rel_path: $output")
    printf "  FAILED: %s\n" "$output"
  fi
done

verbose "All repos processed, generating summary"

# Summary
printf "\n============================\n"
printf "  x-sync summary\n"
printf "============================\n"
printf "  Success:   %d\n" "${#successes[@]}"
printf "  Conflicts: %d\n" "${#conflicts[@]}"
printf "  Failures:  %d\n" "${#failures[@]}"

if [ ${#conflicts[@]} -gt 0 ]; then
  printf "\nConflicts:\n"
  for c in "${conflicts[@]}"; do
    printf "  - %s\n" "$c"
  done
fi

if [ ${#failures[@]} -gt 0 ]; then
  printf "\nFailures:\n"
  for f in "${failures[@]}"; do
    printf "  - %s\n" "$f"
  done
fi

if [ ${#conflicts[@]} -gt 0 ] || [ ${#failures[@]} -gt 0 ]; then
  exit 1
fi
