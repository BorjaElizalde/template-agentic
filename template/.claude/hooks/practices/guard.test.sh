#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for the guard's protocol (layer lookup, verdict levels, fail-open paths), for
# the reason form in lib.jq, and for this template's own layer, the skip lists' gateignore.jq.
# Run from any checkout: bash .claude/hooks/practices/guard.test.sh
# The guard runs from a copy beside a fixture registry whose single practice turns the words STOP
# and REMIND on an added line into that level, and stops a SKIP: line whose text after it is not
# a reason in the form, so no stack practice is involved.
# Expect 2 = stopped, R = goes on with a reminder, 0 = silent.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; NOGIT="$(mktemp -d)"
trap 'rm -rf "$WORK" "$NOGIT"' EXIT
mkdir -p "$WORK/practices"
cp "$HERE/guard.sh" "$HERE/lib.jq" "$HERE/gateignore.jq" "$WORK/practices/"
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
    (if has("REMIND") then {level: "remind", text: "reminded"} else empty end),
    (if has("SKIP:") and (sub(".*SKIP:\\s*"; "") | reason_form | not) then
       {level: "stop", text: reason_steps("skipping"; "the skip"; "acme-lint")} else empty end);
EOF
}

check() {  # check <want> <desc> <payload>
  local out code got
  out="$(bash "$GUARD" <<<"$3" 2>/dev/null)"; code=$?
  got="$code"
  [ "$code" -eq 0 ] && [[ "$out" == *additionalContext* ]] && got=R
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $2"; fi
}

write() { jq -n --arg p "$1" --arg c "$2" '{tool_input:{file_path:$p, content:$c}}'; }
edit() { jq -n --arg p "$1" --arg o "$2" --arg n "$3" '{tool_input:{file_path:$p, old_string:$o, new_string:$n}}'; }

PROJECT_LIST="$REPO/.github/gateignore"
STACK_LIST="$REPO/.github/gate-checks/gateignore"
REASON="# No check reads Markdown. Tried running the checks on it, but they read no Markdown."

echo "-- no registry: the stack layer is absent, only the skip lists are judged"
check 0 "STOP with no registry"           "$(write "$REPO/a.txt" "STOP")"
check 2 "a skip-list pattern with no reason" "$(write "$PROJECT_LIST" '*.md')"

registry
echo "-- verdict levels"
check 2 "added STOP"                      "$(write "$REPO/a.txt" "STOP")"
check R "added REMIND"                    "$(write "$REPO/a.txt" "REMIND")"
check 0 "nothing to report"               "$(write "$REPO/a.txt" "fine")"
check 2 "stop beats remind"               "$(write "$REPO/a.txt" $'REMIND\nSTOP')"

echo "-- the reason form: a why, then one Tried ..., but ... sentence per alternative"
TRIED='Tried the fix the rule gives, but it breaks the callers.'
check 0 "a why and a Tried sentence"      "$(write "$REPO/a.txt" "SKIP: the loader defines it. $TRIED")"
check 0 "two Tried sentences"             "$(write "$REPO/a.txt" "SKIP: the loader defines it. $TRIED Tried a stub, but it drifts.")"
check 2 "a why, no Tried sentence"        "$(write "$REPO/a.txt" "SKIP: the loader defines it")"
check 2 "Tried with no but"               "$(write "$REPO/a.txt" "SKIP: the loader defines it. Tried importing it.")"
check 2 "Tried with no why before it"     "$(write "$REPO/a.txt" "SKIP: $TRIED")"
check 2 "a second Tried with no but"      "$(write "$REPO/a.txt" "SKIP: the loader defines it. $TRIED Tried a stub.")"
out="$(bash "$GUARD" <<<"$(write "$REPO/a.txt" "SKIP: no reason")" 2>&1 >/dev/null)"
if [[ "$out" == *"tool's docs (acme-lint)"* && "$out" == *"Tried <alternative>, but <why it was discarded>"* ]]
then pass=$((pass+1)); echo "PASS the stop names the stack's tools and spells out the form"
else fail=$((fail+1)); echo "FAIL the stop names the stack's tools and spells out the form"; fi

echo "-- only added lines are judged"
printf 'STOP\nold\n' >"$REPO/b.txt"
check 0 "edit beside an existing STOP"    "$(edit "$REPO/b.txt" "old" "new")"
check 0 "edit that removes a STOP"        "$(edit "$REPO/b.txt" "STOP" "gone")"
check 2 "edit that adds a STOP"           "$(edit "$REPO/b.txt" "old" "STOP again")"

echo "-- fail-open paths"
check 0 "file of no kind"                 "$(write "$REPO/a.md" "STOP")"
check 0 "git-ignored file"                "$(write "$REPO/ignored.txt" "STOP")"
check 0 "outside a git repo"              "$(write "$NOGIT/a.txt" "STOP")"
check 0 "new file in a new folder"        "$(write "$REPO/new/dir/a.txt" "fine")"
check 2 "new file in a new folder, STOP"  "$(write "$REPO/new/dir/a.txt" "STOP")"
check 0 "no file path"                    '{"tool_input":{}}'

echo "-- the skip lists: each added pattern takes its reason on the # lines directly above it"
check 0 "the project's list, a pattern with its reason" "$(write "$PROJECT_LIST" "$REASON"$'\n*.md')"
check 2 "the project's list, a pattern with no reason" "$(write "$PROJECT_LIST" "# Markdown"$'\n*.md')"
check 2 "the stack's list, a pattern with no reason" "$(write "$STACK_LIST" '*.md')"
check 2 "a reason with a blank line below it" "$(write "$PROJECT_LIST" "$REASON"$'\n\n*.md')"
check 0 "a ! pattern, which runs more checks" "$(write "$PROJECT_LIST" '!docs/api.md')"
check 0 "comment lines alone"             "$(write "$PROJECT_LIST" '# Paths no check reads.')"
mkdir -p "$(dirname "$PROJECT_LIST")"
printf '%s\n%s\n' "$REASON" '*.md' >"$PROJECT_LIST"
check 2 "an edit that adds a second pattern under the first's reason" "$(edit "$PROJECT_LIST" '*.md' $'*.md\ndocs/**')"
check 0 "an edit that only rewords a reason" "$(edit "$PROJECT_LIST" 'No check reads Markdown.' 'No check reads a Markdown file.')"
out="$(bash "$GUARD" <<<"$(write "$PROJECT_LIST" 'notebooks/**')" 2>&1 >/dev/null)"
if [[ "$out" == *"- \`notebooks/**\`"* && "$out" == *"Tried <alternative>, but <why it was discarded>"* ]]
then pass=$((pass+1)); echo "PASS the stop names the pattern and spells out the form"
else fail=$((fail+1)); echo "FAIL the stop names the pattern and spells out the form"; fi

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
