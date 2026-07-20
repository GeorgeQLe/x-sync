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

BASE_DIR="$(pwd)"
failures=()
conflicts=()
successes=()
skipped=()

skip_repo() {
  local rel_path="$1"
  local reason="$2"
  local one_line="${reason//$'\n'/; }"
  skipped+=("$rel_path: $one_line")
  printf "  SKIPPED: %s\n" "$one_line"
}

is_skip_pull_output() {
  local output="$1"
  echo "$output" | grep -Eqi \
    "couldn't find remote ref|could not read from remote repository|repository .* not found|repository not found|does not appear to be a git repository|no such remote ref"
}

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
mapfile -t git_dirs < <(find "$BASE_DIR" -path "*/.build/*" -prune -o -type d -name ".git" -print | sort)
stop_spinner
printf "Found %d git repo(s). Syncing...\n" "${#git_dirs[@]}"

for gitdir in "${git_dirs[@]}"; do
  repo_dir="$(dirname "$gitdir")"
  rel_path="${repo_dir#"$BASE_DIR"/}"

  verbose "Found git repo at $repo_dir"
  printf "\n=== Pulling: %s ===\n" "$rel_path"

  verbose "Checking for attached HEAD"
  if ! current_branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null); then
    verbose "Detached HEAD — skipping"
    skip_repo "$rel_path" "detached HEAD"
    continue
  fi

  verbose "Checking for remote tracking branch"
  if ! upstream=$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    verbose "No upstream tracking branch — skipping"
    skip_repo "$rel_path" "no upstream tracking branch for $current_branch"
    continue
  fi

  verbose "Checking for local upstream ref"
  if ! git -C "$repo_dir" rev-parse --verify --quiet "$upstream" >/dev/null; then
    verbose "Upstream ref is missing locally — skipping"
    skip_repo "$rel_path" "upstream ref $upstream is missing"
    continue
  fi

  verbose "Running git pull"
  output=""
  if output=$(git -C "$repo_dir" pull 2>&1); then
    verbose "Pull succeeded, checking output for conflicts"
    if echo "$output" | grep -qi "conflict"; then
      verbose "Conflict detected in $rel_path"
      conflicts+=("$rel_path")
      printf "  CONFLICT: %s\n" "$output"
    else
      verbose "Pull completed cleanly for $rel_path"
      successes+=("$rel_path")
      printf "  %s\n" "$output"
    fi
  else
    verbose "Pull command failed for $rel_path"
    if echo "$output" | grep -qi "conflict"; then
      verbose "Conflict detected in $rel_path"
      conflicts+=("$rel_path")
      printf "  CONFLICT: %s\n" "$output"
    elif is_skip_pull_output "$output"; then
      verbose "Pull failed because remote/upstream is unavailable; skipping $rel_path"
      skip_repo "$rel_path" "$output"
    else
      verbose "Recording failure for $rel_path"
      failures+=("$rel_path: $output")
      printf "  FAILED: %s\n" "$output"
    fi
  fi
done

verbose "All repos processed, generating summary"

# Summary
printf "\n============================\n"
printf "  x-sync summary\n"
printf "============================\n"
printf "  Success:   %d\n" "${#successes[@]}"
printf "  Skipped:   %d\n" "${#skipped[@]}"
printf "  Conflicts: %d\n" "${#conflicts[@]}"
printf "  Failures:  %d\n" "${#failures[@]}"

if [ ${#skipped[@]} -gt 0 ]; then
  printf "\nSkipped:\n"
  for s in "${skipped[@]}"; do
    printf "  - %s\n" "$s"
  done
fi

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
