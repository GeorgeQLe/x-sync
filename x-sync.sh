#!/usr/bin/env bash
set -euo pipefail

# x-sync: Recursively find git repos and pull from their remotes.
# Reports merge conflicts and failures at the end.

BASE_DIR="$(pwd)"
failures=()
conflicts=()
successes=()

# Find all directories containing a .git folder
while IFS= read -r gitdir; do
  repo_dir="$(dirname "$gitdir")"
  rel_path="${repo_dir#"$BASE_DIR"/}"

  printf "\n=== Pulling: %s ===\n" "$rel_path"

  output=""
  if output=$(git -C "$repo_dir" pull 2>&1); then
    if echo "$output" | grep -qi "conflict"; then
      conflicts+=("$rel_path")
      printf "  CONFLICT: %s\n" "$output"
    else
      successes+=("$rel_path")
      printf "  %s\n" "$output"
    fi
  else
    if echo "$output" | grep -qi "conflict"; then
      conflicts+=("$rel_path")
      printf "  CONFLICT: %s\n" "$output"
    else
      failures+=("$rel_path: $output")
      printf "  FAILED: %s\n" "$output"
    fi
  fi
done < <(find "$BASE_DIR" -type d -name ".git" | sort)

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
