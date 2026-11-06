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
# GitHub's own expressions, ${{ }}, are not Jinja.
expect "no Jinja left in rendered files" bash -c "! grep -rIl -E '(^|[^\$])\\{\\{|\\{%' --exclude-dir=.git '$D'"
expect "config carries the answers" bash -c "grep -qx 'ISSUES_REPO=acme/tasks' '$D/.claude/agentic.conf' && grep -qx 'WORKTREE_ROOT=../worktrees' '$D/.claude/agentic.conf' && grep -qx 'DEPLOY_WORKFLOW=' '$D/.claude/agentic.conf'"
expect "settings.json is JSON" jq empty "$D/.claude/settings.json"
GATE="$D/.github/workflows/gate.yaml"
expect "the Gate workflow is a valid workflow" uvx --quiet check-jsonschema --builtin-schema vendor.github-workflows "$GATE"
expect "the Gate workflow runs the stack's checks, never make" bash -c "
  grep -qx '      - uses: ./.github/actions/stack-gate' '$GATE' && ! grep -v '^[[:space:]]*#' '$GATE' | grep -qw make"
expect "renovate.json is valid Renovate config" uvx --quiet check-jsonschema --schemafile https://docs.renovatebot.com/renovate-schema.json "$D/renovate.json"
expect "Renovate leaves the template's CI files to the update PR" jq -e '.["github-actions"].ignorePaths as $p
  | any($p[]; . == ".github/workflows/gate.yaml") and any($p[]; . == ".github/actions/stack-gate/**")' "$D/renovate.json"
expect "the release skill doesn't say CI runs make gate" bash -c "! grep -q 'make gate' '$D/.claude/skills/release/SKILL.md'"
X="$OUT/existing"
mkdir -p "$X"
printf '{"extends": ["config:base"]}\n' >"$X/renovate.json"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks "$OUT/src" "$X"
expect "a first copy keeps the project's renovate.json" bash -c "[ \"\$(cat '$X/renovate.json')\" = '{\"extends\": [\"config:base\"]}' ]"
expect "the task plugin's manifest names it task" bash -c "[ \"\$(jq -r .name '$D/.claude/skills/task/.claude-plugin/plugin.json')\" = task ]"
expect "no .claude/scripts folder is rendered" test ! -e "$D/.claude/scripts"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "bash-guard suite" bash "$D/.claude/hooks/bash-guard.test.sh"
expect "practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "memory checker suite" bash "$D/.claude/hooks/memory/guard.test.sh"
expect "task.sh suite" bash "$D/.claude/skills/task/scripts/task.test.sh"
expect "seeded memory index is clean" bash "$D/.claude/hooks/memory/staleness.sh" "$D/.claude/memory"
expect "point-memory targets this checkout" bash -c "bash '$D/.claude/skills/task/scripts/task.sh' point-memory >/dev/null &&
  [ \"\$(jq -r .autoMemoryDirectory '$D/.claude/settings.local.json')\" = \"\$(cd '$D' && pwd -P)/.claude/memory\" ]"
expect "pull-request closes issues in the issues repo" grep -q 'Closes acme/tasks#<n>' "$D/.claude/skills/pull-request/SKILL.md"
expect "task skills name the issues repo" bash -c "grep -q 'gh issue create -R acme/tasks' '$D/.claude/skills/task/skills/start/SKILL.md' && grep -q 'gh issue close <n> -R acme/tasks' '$D/.claude/skills/task/skills/finish/SKILL.md'"
expect "session prompt names the issues repo" grep -q 'the acme/tasks issue' "$D/.claude/skills/task/session/prompt.md"
expect "no release facts file; without a deploy, release waits for none" bash -c "[ ! -e '$D/.claude/release.md' ] && grep -q 'has no deploy' '$D/.claude/skills/release/SKILL.md' && ! grep -q 'await-run.sh' '$D/.claude/skills/release/SKILL.md'"
expect "session files sit only in the task plugin" bash -c "[ -z \"\$(find '$D/.claude' -maxdepth 1 -name 'subagent-session-*')\" ] && jq empty '$D/.claude/skills/task/session/settings.json'"

# This repository is a project of its own template: on a copy of the working tree, make render
# (which the pre-commit hook runs on every commit that changes template/) must leave .claude/ as it is.
mkdir -p "$OUT/self"
(cd "$ROOT" && tar --exclude .git -cf - .) | tar -xf - -C "$OUT/self"
harness_in_step() {
  local drift
  make -s -C "$OUT/self" render >/dev/null || return 1
  drift="$(diff -rq "$ROOT/.claude" "$OUT/self/.claude")" && return 0
  sed "s#$OUT/self#render#g; s#$ROOT#repository#g; s/^/FAIL /" <<<"$drift"
  return 1
}
expect "this repository's harness is in step with the template (make render changes nothing)" harness_in_step

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
