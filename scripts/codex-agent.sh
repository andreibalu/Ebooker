#!/usr/bin/env bash
#
# Run one bounded Codex implementation slice in an isolated git worktree.
#
# Use this script only for parallel fan-out, where two or more slices must not
# collide on edits. A single slice runs with `codex exec` in the current checkout.
#
#   scripts/codex-agent.sh <slice> <spec-file>                 # gpt-6.1-sol, medium
#   scripts/codex-agent.sh <slice> <spec-file> --effort low
#   scripts/codex-agent.sh <slice> --cleanup
#
# Every run names its model and effort explicitly, so nothing is inherited
# implicitly from ~/.codex/config.toml or .codex/config.toml. The model policy
# lives in ~/.claude/CLAUDE.md; update ALLOWED_MODELS when it changes.

set -euo pipefail

DEFAULT_MODEL="gpt-6.1-sol"
DEFAULT_EFFORT="medium"
ALLOWED_MODELS="gpt-6.1-sol"

usage() {
  cat <<'USAGE'
Usage: scripts/codex-agent.sh <slice> <spec-file> [options]
       scripts/codex-agent.sh <slice> --cleanup

Arguments:
  <slice>        Short name; becomes branch codex/<slice> and .worktrees/<slice>
  <spec-file>    Path to the specification Codex should implement

Options:
  --model <m>    Codex model (default and only allowed: gpt-6.1-sol)
  --effort <e>   none|minimal|low|medium|high|xhigh|max (default: medium)
  --base <ref>   Branch the worktree from this ref (default: HEAD)
  --cleanup      Remove the worktree and its branch, then exit
  -h, --help     Show this message
USAGE
}

SLICE=""; SPEC=""; MODEL=""; EFFORT=""; BASE="HEAD"; CLEANUP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --model)   MODEL="${2:?--model needs a value}"; shift 2 ;;
    --effort)  EFFORT="${2:?--effort needs a value}"; shift 2 ;;
    --base)    BASE="${2:?--base needs a value}"; shift 2 ;;
    --cleanup) CLEANUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)        echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)         if [ -z "$SLICE" ]; then SLICE="$1"; elif [ -z "$SPEC" ]; then SPEC="$1";
               else echo "Unexpected argument: $1" >&2; exit 2; fi; shift ;;
  esac
done

[ -n "$SLICE" ] || { usage >&2; exit 2; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="$REPO_ROOT/.worktrees/$SLICE"
BRANCH="codex/$SLICE"
RUNS="$REPO_ROOT/.codex-runs"

if [ "$CLEANUP" -eq 1 ]; then
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" 2>/dev/null || true
  git -C "$REPO_ROOT" branch -D "$BRANCH" 2>/dev/null || true
  git -C "$REPO_ROOT" worktree prune
  echo "Removed worktree $WORKTREE and branch $BRANCH."
  exit 0
fi

[ -n "$SPEC" ] || { echo "Missing <spec-file>." >&2; usage >&2; exit 2; }
[ -f "$SPEC" ] || { echo "Spec file not found: $SPEC" >&2; exit 1; }

MODEL="${MODEL:-$DEFAULT_MODEL}"

case " $ALLOWED_MODELS " in
  *" $MODEL "*) ;;
  *) echo "error: $MODEL is not used here. Allowed: $ALLOWED_MODELS (policy in ~/.claude/CLAUDE.md)." >&2
     exit 2 ;;
esac

EFFORT="${EFFORT:-$DEFAULT_EFFORT}"

mkdir -p "$RUNS"
if [ ! -d "$WORKTREE" ]; then
  git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE" "$BASE" >&2
fi

SPEC_ABS="$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")"
FINAL="$RUNS/$SLICE.final.md"
LOG="$RUNS/$SLICE.log"

echo "slice=$SLICE model=$MODEL effort=$EFFORT worktree=$WORKTREE" >&2

codex exec - \
  --model "$MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  -c approval_policy="never" \
  -c sandbox_workspace_write.network_access=true \
  --sandbox workspace-write \
  --cd "$WORKTREE" \
  --output-last-message "$FINAL" \
  < "$SPEC_ABS" 2>&1 | tee "$LOG"

echo >&2
echo "--- changes in $BRANCH ---" >&2
git -C "$WORKTREE" add -A >&2
git -C "$WORKTREE" diff --cached --stat >&2
echo >&2
echo "final message: $FINAL" >&2
echo "full log:      $LOG" >&2
