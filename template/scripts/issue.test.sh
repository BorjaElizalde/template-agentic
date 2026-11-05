#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for issue.sh's worktree layout. Run from any checkout: bash scripts/issue.test.sh
# Two clones of one throwaway origin, named backend and frontend, stand in for two repositories; a
# stub gh answers the issue-title lookup.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

mkdir -p "$WORK/bin" "$WORK/seed/scripts" "$WORK/seed/.claude" "$WORK/repos"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$3" in
  42) echo "Name make close_claude_session in backend CLAUDE.md" ;;
  7) echo "Second task" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

cp "$HERE/issue.sh" "$WORK/seed/scripts/"
printf 'ISSUES_REPO=acme/tasks\nWORKTREE_ROOT=../worktrees\n' >"$WORK/seed/.claude/agentic.conf"
git init -q -b develop "$WORK/seed"
git -C "$WORK/seed" add -A
git -C "$WORK/seed" -c user.name=t -c user.email=t@t commit -qm seed
git clone -q --bare "$WORK/seed" "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repos/backend"
git clone -q "$WORK/origin.git" "$WORK/repos/frontend"

check() {  # check <desc> <command...>
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS $1"
  else fail=$((fail+1)); echo "FAIL $1"; fi
}
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }
memory_of() { jq -r .autoMemoryDirectory "$1/.claude/settings.local.json"; }

ISSUE42="$WORK/repos/worktrees/42-name-make-close-claude-session-in"
echo "-- one folder per issue, one subfolder per repository"
check "backend worktree created"          "$WORK/repos/backend/scripts/issue.sh" worktree 42
check "it sits at <root>/<n>-<slug>/backend" test -d "$ISSUE42/backend"
check "its branch is feat/<n>-<slug>"      test "$(branch_of "$ISSUE42/backend")" = feat/42-name-make-close-claude-session-in
check "it branches off origin/develop"     git -C "$ISSUE42/backend" merge-base --is-ancestor origin/develop HEAD
check "its memory points at itself"        test "$(memory_of "$ISSUE42/backend")" = "$ISSUE42/backend/.claude/memory"
check "frontend joins the same issue"      "$WORK/repos/frontend/scripts/issue.sh" worktree 42
check "side by side, no collision"         test -d "$ISSUE42/frontend"

echo "-- run from inside a worktree: paths still resolve from the main checkout"
check "worktree for another issue"         "$ISSUE42/backend/scripts/issue.sh" worktree 7 fix
check "it sits beside the first issue"     test -d "$WORK/repos/worktrees/7-second-task/backend"
check "its branch takes the type"          test "$(branch_of "$WORK/repos/worktrees/7-second-task/backend")" = fix/7-second-task
check "point-memory targets that worktree" "$ISSUE42/backend/scripts/issue.sh" point-memory
check "and leaves the main checkout alone" test ! -e "$WORK/repos/backend/.claude/settings.local.json"

echo "-- usage"
check "no command is refused"              bash -c "! '$WORK/repos/backend/scripts/issue.sh'"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
