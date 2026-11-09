#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for project.sh, the dispatcher of the project's own hooks. Run from any
# checkout: bash .claude/hooks/project.test.sh
# The dispatcher runs from a copy beside a fixture project/ folder, so no real project hook runs.
# Each check compares the exit code, stdout and stderr exactly.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$HERE/project.sh" "$WORK/"
PAYLOAD='{"hook_event_name":"Test"}'
pass=0; fail=0

script() {  # script <event>/<name> <body>: an executable bash script in the fixture folder
  mkdir -p "$WORK/project/${1%/*}"
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$WORK/project/$1"
  chmod +x "$WORK/project/$1"
}

check() {  # check <desc> <event> <want-exit> <want-stdout> <want-stderr>
  local out err code
  out="$(bash "$WORK/project.sh" "$2" <<<"$PAYLOAD" 2>"$WORK/stderr")"; code=$?
  err="$(cat "$WORK/stderr")"
  if [ "$code" = "$3" ] && [ "$out" = "$4" ] && [ "$err" = "$5" ]; then
    pass=$((pass+1)); echo "PASS $1"
  else
    fail=$((fail+1)); echo "FAIL $1: got exit $code, stdout '$out', stderr '$err'"
  fi
}

check "a missing folder exits 0 at once" Stop 0 "" ""

mkdir -p "$WORK/project/Stop"
check "an empty folder exits 0" Stop 0 "" ""

script UserPromptSubmit/20-second 'echo second'
script UserPromptSubmit/10-first 'echo first'
check "two scripts' stdout passes through in name order" UserPromptSubmit 0 $'first\nsecond' ""

script SessionStart/10-a 'cat'
script SessionStart/20-b 'cat'
check "every script reads the payload on stdin" SessionStart 0 "$PAYLOAD"$'\n'"$PAYLOAD" ""

script PreToolUse/10-noisy 'echo noise >&2'
script PreToolUse/20-block 'echo blocked >&2; exit 2'
script PreToolUse/30-after 'echo ran'
check "the first exit 2 stops the run, with its own stderr" PreToolUse 2 "" "blocked"

script PostToolUse/10-broken 'echo "no such file" >&2; exit 3'
script PostToolUse/20-after 'echo ran'
check "a failing script is reported by name, and the rest still run" PostToolUse 1 "ran" \
  "project hook PostToolUse/10-broken failed (exit 3): no such file"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
