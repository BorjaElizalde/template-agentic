#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for main-clean-guard.sh (the copy sitting next to this file).
# Run from any checkout: bash .claude/hooks/main-clean-guard.test.sh
# The guard remembers what it has named, so the cases run in order on one fixture repository, each
# from the state the case before it left.
set -u
GUARD="$(cd "$(dirname "$0")" && pwd)/main-clean-guard.sh"
pass=0; fail=0
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

M="$FIX/main"
git init -q "$M"
printf 'ignored.log\n' >"$M/.gitignore"
printf 'one\n' >"$M/tracked.txt"
git -C "$M" add -A
git -C "$M" -c user.name=t -c user.email=t@t commit -qm init
git -C "$M" worktree add -q --detach "$FIX/worktree"
mkdir "$FIX/no-repo"
git init -q "$FIX/broken"
printf 'junk\n' >"$FIX/broken/.git/index"   # rev-parse still answers; status can't read the index

after() {  # after <dir> <want-exit> <desc> [<phrase>|!<phrase>]...: run the guard after a Bash call
  # in <dir>. Its stderr must hold each <phrase> and no !<phrase>; exit 0 must be silent, and stdout,
  # which PostToolUse discards, stays empty.
  local dir="$1" exp="$2" desc="$3" got out err p bad=""
  shift 3
  out="$(jq -n --arg d "$dir" '{cwd:$d,tool_input:{command:"true"}}' | bash "$GUARD" 2>"$FIX/err")"
  got=$?
  err="$(cat "$FIX/err")"
  [ "$got" -eq "$exp" ] || bad="want exit $exp, got $got"
  [ -z "$out" ] || bad="wrote to stdout"
  [ "$exp" -ne 0 ] || [ -z "$err" ] || bad="exit 0 but stderr"
  for p in "$@"; do
    case "$p" in
      !*) [[ "$err" != *"${p#!}"* ]] || bad="names '${p#!}'" ;;
      *) [[ "$err" == *"$p"* ]] || bad="does not name '$p'" ;;
    esac
  done
  if [ -z "$bad" ]; then pass=$((pass+1)); echo "PASS ($got) $desc"
  else fail=$((fail+1)); echo "FAIL ($bad) $desc"; sed 's/^/      /' <<<"$err"; fi
}

echo "-- left alone"
after "$FIX/no-repo" 0 "no repository"
after "$FIX/broken" 0 "git can't answer"
after "$M" 0 "a clean main checkout"
: >"$M/ignored.log"
after "$M" 0 "an ignored file"
: >"$M/out.csv"
: >"$FIX/worktree/scratch.txt"
echo two >>"$FIX/worktree/tracked.txt"
after "$FIX/worktree" 0 "a linked worktree, even with its main checkout changed"

echo "-- named once"
after "$M" 2 "a new untracked file, with the fix" '?? out.csv' "task's worktree" '!ignored.log'
after "$M" 0 "the same changes after a later call"
echo two >>"$M/tracked.txt"
after "$M" 2 "a changed tracked file, named alone" ' M tracked.txt' '!out.csv'
rm "$M/out.csv"
after "$M" 0 "a change undone"
: >"$M/out.csv"
after "$M" 2 "a file removed and made again" '?? out.csv' '!tracked.txt'
git -C "$M" checkout -q -- tracked.txt
rm "$M/out.csv"
after "$M" 0 "clean again"
echo two >>"$M/tracked.txt"
after "$M" 2 "a change made again after the checkout came clean" ' M tracked.txt'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
