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

# Find all directories containing a .git folder
while IFS= read -r gitdir; do
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
    else
      verbose "Recording failure for $rel_path"
      failures+=("$rel_path: $output")
      printf "  FAILED: %s\n" "$output"
    fi
  fi
done < <(find "$BASE_DIR" -type d -name ".git" | sort)

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
