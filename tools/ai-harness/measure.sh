#!/bin/bash
# Measures one revision on both passage sets. Usage: measure.sh <git-rev | --worktree> <out-dir>
# Writes <set>-<moment|recap>.jsonl and run.txt (revision, host, toolchain) to <out-dir>.
set -euo pipefail
rev="$1"; out="$2"; here="$(cd "$(dirname "$0")" && pwd)"; repo="$(git -C "$here" rev-parse --show-toplevel)"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
if [ "$rev" = "--worktree" ]; then
  root="$repo"
  echo "source: working tree at $(git -C "$repo" rev-parse HEAD), $(git -C "$repo" status --porcelain -- Pageless | wc -l | tr -d ' ') changed files under Pageless/" > "$out/run.txt"
else
  root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT
  git -C "$repo" archive "$rev" Pageless | tar -x -C "$root"
  echo "source: $rev = $(git -C "$repo" rev-parse "$rev")" > "$out/run.txt"
fi
{ sw_vers | tr '\n' ' '; echo; swiftc --version 2>&1 | head -1; date -u +%FT%TZ; } >> "$out/run.txt"
"$here/build.sh" "$root" "$out/harness"
for set in tuned heldout; do
  for mode in moment recap; do
    "$out/harness" "$here/corpus/$set.json" "$mode" "$out/$set-$mode.jsonl"
  done
done
