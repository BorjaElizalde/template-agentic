#!/usr/bin/env bash
# Renders the template and runs the rendered harness's own tests, the way a project gets it.
# Needs uv, git and jq.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
fail=0

# A plain copy, so the render is the working tree whether or not it is committed or tagged.
mkdir -p "$OUT/src"
(cd "$ROOT" && tar --exclude .git -cf - .) | tar -xf - -C "$OUT/src"

expect() {  # expect <desc> <command...>; a failure prints the command's own lines that report it
  local out
  if out="$("${@:2}" 2>&1)"; then echo "PASS $1"
  else echo "FAIL $1"; grep -E 'FAIL|rror' <<<"$out" | head -20 | sed 's/^/    /'; fail=1; fi
}

D="$OUT/project"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks "$OUT/src" "$D"
git -C "$D" init -q
git -C "$D" add -A
git -C "$D" -c user.name=t -c user.email=t@t commit -qm render

expect "no Makefile, harness.mk or CLAUDE.md written" bash -c "[ ! -e '$D/Makefile' ] && [ ! -e '$D/harness.mk' ] && [ ! -e '$D/CLAUDE.md' ]"
expect "the shared rules load without an import" test -f "$D/.claude/rules/agentic.md"
expect "answers land in .copier-answers.agentic.yaml" test -f "$D/.copier-answers.agentic.yaml"
expect "no .yml file in the template or the project" bash -c "[ -z \"\$(find '$ROOT' '$D' -name '*.yml' -not -path '*/.git/*')\" ]"
expect "no Jinja left in rendered files" bash -c "! grep -rIl -e '{{' -e '{%' --exclude-dir=.git '$D'"
expect "config carries the answers" bash -c "grep -qx 'ISSUES_REPO=acme/tasks' '$D/.claude/agentic.conf' && grep -qx 'WORKTREE_ROOT=../worktrees' '$D/.claude/agentic.conf'"
expect "settings.json is JSON" jq empty "$D/.claude/settings.json"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "bash-guard suite" bash "$D/.claude/hooks/bash-guard.test.sh"
expect "practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "memory checker suite" bash "$D/.claude/scripts/check-memory-staleness.test.sh"
expect "task.sh suite" bash "$D/.claude/scripts/task.test.sh"
expect "seeded memory index is clean" bash "$D/.claude/scripts/check-memory-staleness.sh" "$D/.claude/memory"
expect "point-memory targets this checkout" bash -c "bash '$D/.claude/scripts/task.sh' point-memory >/dev/null &&
  [ \"\$(jq -r .autoMemoryDirectory '$D/.claude/settings.local.json')\" = \"\$(cd '$D' && pwd -P)/.claude/memory\" ]"
expect "pull-request closes issues in the issues repo" grep -q 'Closes acme/tasks#<n>' "$D/.claude/skills/pull-request/SKILL.md"
expect "task skills name the issues repo" bash -c "grep -q 'gh issue create -R acme/tasks' '$D/.claude/skills/start-task/SKILL.md' && grep -q 'gh issue close <n> -R acme/tasks' '$D/.claude/skills/finish-task/SKILL.md'"
expect "session prompt names the issues repo" grep -q 'the acme/tasks issue' "$D/.claude/subagent-session-prompt.md"

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
