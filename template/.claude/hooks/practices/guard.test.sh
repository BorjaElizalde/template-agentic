#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for the guard's protocol: registry lookup, verdict levels, fail-open paths.
# Run from any checkout: bash .claude/hooks/practices/guard.test.sh
# The guard runs from a copy beside a fixture registry whose single practice turns the words STOP,
# ASK and REMIND on an added line into that level, so no stack practice is involved.
# Expect 2 = stopped, A = asks the owner, R = goes on with a reminder, 0 = silent.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; NOGIT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$NOGIT"' EXIT
mkdir -p "$WORK/practices"
cp "$HERE/guard.sh" "$HERE/lib.jq" "$WORK/practices/"
GUARD="$WORK/practices/guard.sh"
REPO="$WORK/repo"
git init -q "$REPO"
printf 'ignored.txt\n' >"$REPO/.gitignore"
pass=0; fail=0

registry() {
  cat >"$WORK/practices/registry.jq" <<'EOF'
include "lib";
def kind($path): if $path | endswith(".txt") then "text" else null end;
def practices($ctx; $kind):
  $ctx.added[].line
  | (if has("STOP") then {level: "stop", text: "stopped"} else empty end),
    (if has("ASK") then {level: "ask", text: "asked"} else empty end),
    (if has("REMIND") then {level: "remind", text: "reminded"} else empty end);
EOF
}

check() {  # check <want> <desc> <payload>
  local out code got
  out="$(bash "$GUARD" <<<"$3" 2>/dev/null)"; code=$?
  got="$code"
  if [ "$code" -eq 0 ]; then
    [[ "$out" == *'"ask"'* ]] && got=A
    [[ "$out" == *additionalContext* ]] && got=R
  fi
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $2"; fi
}

write() { jq -n --arg p "$1" --arg c "$2" '{tool_input:{file_path:$p, content:$c}}'; }
edit() { jq -n --arg p "$1" --arg o "$2" --arg n "$3" '{tool_input:{file_path:$p, old_string:$o, new_string:$n}}'; }

echo "-- no registry: the stack layer is absent, nothing runs"
check 0 "STOP with no registry"           "$(write "$REPO/a.txt" "STOP")"

registry
echo "-- verdict levels"
check 2 "added STOP"                      "$(write "$REPO/a.txt" "STOP")"
check A "added ASK"                       "$(write "$REPO/a.txt" "ASK")"
check R "added REMIND"                    "$(write "$REPO/a.txt" "REMIND")"
check 0 "nothing to report"               "$(write "$REPO/a.txt" "fine")"
check 2 "stop beats ask and remind"       "$(write "$REPO/a.txt" $'ASK\nSTOP\nREMIND')"
check A "ask beats remind"                "$(write "$REPO/a.txt" $'REMIND\nASK')"

echo "-- only added lines are judged"
printf 'STOP\nold\n' >"$REPO/b.txt"
check 0 "edit beside an existing STOP"    "$(edit "$REPO/b.txt" "old" "new")"
check 0 "edit that removes a STOP"        "$(edit "$REPO/b.txt" "STOP" "gone")"
check 2 "edit that adds a STOP"           "$(edit "$REPO/b.txt" "old" "STOP again")"
check 2 "MultiEdit: 2nd edit adds STOP"   "$(jq -n --arg p "$REPO/b.txt" '{tool_input:{file_path:$p,
  edits:[{old_string:"old", new_string:"new"}, {old_string:"new", new_string:"STOP now"}]}}')"

echo "-- fail-open paths"
check 0 "file of no kind"                 "$(write "$REPO/a.md" "STOP")"
check 0 "git-ignored file"                "$(write "$REPO/ignored.txt" "STOP")"
check 0 "outside a git repo"              "$(write "$NOGIT/a.txt" "STOP")"
check 0 "new file in a new folder"        "$(write "$REPO/new/dir/a.txt" "fine")"
check 2 "new file in a new folder, STOP"  "$(write "$REPO/new/dir/a.txt" "STOP")"
check 0 "no file path"                    '{"tool_input":{}}'

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
