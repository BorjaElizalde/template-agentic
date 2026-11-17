#!/usr/bin/env bash
# Renders the template and runs the rendered harness's own tests, the way a project gets it.
# Needs uv, git and jq.
# Every function here runs: expect calls each check by the name it is given. Tried one directive on
# each such function, but the cause is expect, which every check in this file goes through.
# shellcheck disable=SC2329
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

expect "the make fragment is .claude/agentic.mk, and no Makefile or CLAUDE.md is written" bash -c "[ -f '$D/.claude/agentic.mk' ] && [ ! -e '$D/Makefile' ] && [ ! -e '$D/CLAUDE.md' ]"
expect "the shared rules load without an import" bash -c "[ -f '$D/.claude/rules/agentic.md' ] && [ -f '$D/.claude/rules/conventions.md' ]"
expect "answers land in .copier-answers.agentic.yaml" test -f "$D/.copier-answers.agentic.yaml"
expect "no .yml file in the template or the project" bash -c "[ -z \"\$(find '$ROOT' '$D' -name '*.yml' -not -path '*/.git/*')\" ]"
# GitHub's own expressions, ${{ }}, are not Jinja.
expect "no Jinja left in rendered files" bash -c "! grep -rIl -E '(^|[^\$])\\{\\{|\\{%' --exclude-dir=.git '$D'"
expect "config carries the answers" bash -c "grep -qx 'ISSUES_REPO=acme/tasks' '$D/.claude/agentic.conf' && grep -qx 'WORKTREE_ROOT=../worktrees' '$D/.claude/agentic.conf' && grep -qx 'DEPLOY_WORKFLOW=' '$D/.claude/agentic.conf' && grep -qx 'AGENT_MERGES=false' '$D/.claude/agentic.conf'"
expect "by default the pull-request skill leaves the merge to the owner" bash -c "! grep -q 'gh pr merge' '$D/.claude/skills/pull-request/SKILL.md'"
AM="$OUT/agent-merges"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks --data agent_merges=true "$OUT/src" "$AM"
expect "agent_merges reaches agentic.conf" grep -qx 'AGENT_MERGES=true' "$AM/.claude/agentic.conf"
expect "with agent_merges the pull-request skill merges a pinned squash" bash -c "
  grep -qF 'gh pr merge <n> --squash --match-head-commit <sha>' '$AM/.claude/skills/pull-request/SKILL.md' &&
  grep -qF 'Bash(gh pr merge:*)' '$AM/.claude/skills/pull-request/SKILL.md'"
expect "settings.json is JSON" jq empty "$D/.claude/settings.json"
# $CLAUDE_PROJECT_DIR is text in the hook command, for Claude Code to expand. Tried double quotes,
# but then each " and $ of the jq program needs a backslash.
# shellcheck disable=SC2016
expect "a session that starts or resumes runs task.sh on-session-start" jq -e 'any(.hooks.SessionStart[];
  .matcher == "startup|resume" and any(.hooks[];
    .command == "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/task/scripts/task.sh\" on-session-start"))' "$D/.claude/settings.json"
session_start_quiet() {  # the rendered hook command, run in the rendered project, which has no task
  local cmd out
  cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$D/.claude/settings.json")"
  out="$(cd "$D" && CLAUDE_PROJECT_DIR="$D" bash -c "$cmd")" && [ -z "$out" ]
}
expect "the SessionStart hook says nothing where no task is" session_start_quiet
MERGE_ALLOWED='any(.permissions.allow[]; . == "Bash(gh pr merge:*)")'
expect "by default settings.json leaves gh pr merge to a prompt" jq -e "$MERGE_ALLOWED | not" "$D/.claude/settings.json"
expect "with agent_merges settings.json allows gh pr merge" jq -e "$MERGE_ALLOWED" "$AM/.claude/settings.json"
# $d is jq's variable. Tried double quotes, but then each " and $ of the program needs a backslash.
# shellcheck disable=SC2016
expect "settings.json denies claude -p and claude --print" jq -e '.permissions.deny as $d
  | all("Bash(claude -p:*)", "Bash(claude --print:*)"; IN($d[]))' "$D/.claude/settings.json"
# Only /task:finish closes an issue and only task.sh park labels one; delete and transfer are final.
expect "settings.json allows gh issue create, list, view, comment and edit, and no other gh issue or gh label call" jq -e '
  [.permissions.allow[] | select(startswith("Bash(gh issue") or startswith("Bash(gh label"))] | sort
  == ["Bash(gh issue comment:*)", "Bash(gh issue create:*)", "Bash(gh issue edit:*)", "Bash(gh issue list:*)", "Bash(gh issue view:*)"]' \
  "$D/.claude/settings.json"
GATE="$D/.github/workflows/gate.yaml"
expect "the Gate workflow is a valid workflow" uvx --quiet check-jsonschema --builtin-schema vendor.github-workflows "$GATE"
expect "the Gate workflow runs the stack's checks, never make" bash -c "
  grep -qx '      - uses: ./.github/actions/stack-gate' '$GATE' && ! grep -v '^[[:space:]]*#' '$GATE' | grep -qw make"
expect "both preset files and every renovate.json are valid Renovate config" uvx --quiet check-jsonschema \
  --schemafile https://docs.renovatebot.com/renovate-schema.json \
  "$ROOT/renovate/base.json" "$ROOT/renovate/default.json" "$ROOT/renovate.json" "$D/renovate.json"
# "$schema" is a JSON key, not a shell variable. Tried double quotes, but then each " and $ of the
# program needs a backslash.
# shellcheck disable=SC2016
expect "the project's renovate.json is the pointer to the project preset only" jq -e '
  keys == ["$schema", "description", "extends"]
  and .extends == ["github>BorjaElizalde/template-agentic//renovate/default"]' "$D/renovate.json"
# $p is jq's variable. Tried double quotes, but then each " and $ of the program needs a backslash.
# shellcheck disable=SC2016
expect "the project preset is the shared rules, with Renovate off the template's CI files" jq -e '
  .extends == ["github>BorjaElizalde/template-agentic//renovate/base"]
  and (.["github-actions"].ignorePaths as $p
    | any($p[]; . == ".github/workflows/gate.yaml") and any($p[]; . == ".github/actions/stack-gate/**"))' \
  "$ROOT/renovate/default.json"
expect "this repository takes the shared rules only, so Renovate keeps its own CI files' pins current" jq -e \
  '.extends == ["github>BorjaElizalde/template-agentic//renovate/base"] and (has("github-actions") | not)' \
  "$ROOT/renovate.json"
expect "the release skill doesn't say CI runs make gate" bash -c "! grep -q 'make gate' '$D/.claude/skills/release/SKILL.md'"
X="$OUT/existing"
mkdir -p "$X"
printf '{"extends": ["config:base"]}\n' >"$X/renovate.json"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks "$OUT/src" "$X"
expect "a first copy keeps the project's renovate.json" bash -c "[ \"\$(cat '$X/renovate.json')\" = '{\"extends\": [\"config:base\"]}' ]"
expect "the task plugin's manifest names it task" bash -c "[ \"\$(jq -r .name '$D/.claude/skills/task/.claude-plugin/plugin.json')\" = task ]"
expect "no .claude/scripts folder is rendered" test ! -e "$D/.claude/scripts"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "shellcheck finds nothing in any script" bash -c "set -o pipefail; find '$D' '$ROOT/tests' '$ROOT/bundle.sh' -name '*.sh' -exec uvx --quiet --from shellcheck-py==0.11.0.1 shellcheck --format gcc {} + | sed 's/^/FAIL /'"
expect "bash-guard suite" bash "$D/.claude/hooks/bash-guard.test.sh"
expect "worktree-guard suite" bash "$D/.claude/hooks/worktree-guard.test.sh"
expect "practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "memory checker suite" bash "$D/.claude/hooks/memory/guard.test.sh"
expect "task.sh suite" bash "$D/.claude/skills/task/scripts/task.test.sh"
expect "run-gate.sh suite" bash "$D/.claude/skills/gate/scripts/run-gate.test.sh"
expect "await-run.sh suite" bash "$D/.claude/skills/release/scripts/await-run.test.sh"
expect "await-checks.sh suite" bash "$D/.claude/skills/release/scripts/await-checks.test.sh"
expect "seeded memory index is clean" bash "$D/.claude/hooks/memory/staleness.sh" "$D/.claude/memory"
expect "point-memory targets this checkout" bash -c "bash '$D/.claude/skills/task/scripts/task.sh' point-memory >/dev/null &&
  [ \"\$(jq -r .autoMemoryDirectory '$D/.claude/settings.local.json')\" = \"\$(cd '$D' && pwd -P)/.claude/memory\" ]"
expect "pull-request closes issues in the issues repo" grep -q 'Closes acme/tasks#<n>' "$D/.claude/skills/pull-request/SKILL.md"
expect "task skills name the issues repo" bash -c "grep -q 'gh issue create -R acme/tasks' '$D/.claude/skills/task/skills/start/SKILL.md' && grep -q 'gh issue close <n> -R acme/tasks' '$D/.claude/skills/task/skills/finish/SKILL.md' && grep -q 'gh issue view <n> -R acme/tasks --json title,body,comments' '$D/.claude/skills/task/skills/status/SKILL.md'"
expect "session prompt names the issues repo" grep -q 'the acme/tasks issue' "$D/.claude/skills/task/session/prompt.md"
expect "an execution session spawns code-reviewer, code-trimmer, then the simplicity reviewer, with the task's issue, and only code-trimmer on a small change" bash -c "
  grep -q '^Skip steps 1 and 3 when the change is small' '$D/.claude/skills/task/session/execution.md' &&
  grep -q '^1. Spawn the .code-reviewer. agent' '$D/.claude/skills/task/session/execution.md' &&
  grep -q '^2. Spawn the .code-trimmer. agent' '$D/.claude/skills/task/session/execution.md' &&
  grep -q '^3. Spawn one .simplicity-reviewer.' '$D/.claude/skills/task/session/execution.md' &&
  grep -q 'gh issue view <n> -R acme/tasks --json title,body,comments' '$D/.claude/skills/task/session/execution.md'"
expect "with agent_merges an execution session merges its PR as its last step" bash -c "
  grep -q 'stop before its merge step' '$AM/.claude/skills/task/session/execution.md' &&
  grep -q '^4. Merge the PR' '$AM/.claude/skills/task/session/execution.md' &&
  ! grep -qi 'merge' '$D/.claude/skills/task/session/execution.md'"
for reviewer in code-reviewer simplicity-reviewer; do
  REVIEWER="$D/.claude/agents/$reviewer.md"
  expect "$reviewer has no tool that edits, nor memory, which adds Write and Edit" bash -c "
    grep -q '^tools: Read' '$REVIEWER' && ! grep -qE '^(tools:.*(Edit|Write|Agent)|memory:)' '$REVIEWER'"
done
TRIMMER="$D/.claude/agents/code-trimmer.md"
expect "code-trimmer edits and commits, and spawns no agent" bash -c "
  grep -qE '^tools:.*Bash.*Edit' '$TRIMMER' && ! grep -qE '^tools:.*Agent' '$TRIMMER'"
expect "no release facts file; without a deploy, release waits for none" bash -c "[ ! -e '$D/.claude/release.md' ] && grep -q 'has no deploy' '$D/.claude/skills/release/SKILL.md' && ! grep -q 'await-run.sh' '$D/.claude/skills/release/SKILL.md'"
expect "session files sit only in the task plugin" bash -c "[ -z \"\$(find '$D/.claude' -maxdepth 1 -name 'subagent-session-*')\" ] && jq empty '$D/.claude/skills/task/session/settings.json'"

release() {
  git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2" && git -C "$1" tag "$2"
}
S="$OUT/stack"
cp -R "$OUT/src/tests/stack" "$S"
git -C "$S" init -q
bash "$OUT/src/bundle.sh" "$S"
release "$S" v1
NEXT="$OUT/next"
cp -R "$OUT/src" "$NEXT"
printf 'probe\n' >"$NEXT/template/update-probe.txt"
rm "$NEXT/template/.claude/skills/commit/SKILL.md"
printf '{}\n' >"$NEXT/template/renovate.json"
bash "$NEXT/bundle.sh" "$S"
printf 'gate:\n\t@echo v2\n' >"$S/template/Makefile"
release "$S" v2

TWO="$OUT/two-layers"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks "$OUT/src" "$TWO"
# Copier reads an !include that matches no file as empty, and this copy of tests/stack has no agentic/.
uvx --quiet copier copy --quiet --defaults "$OUT/src/tests/stack" "$TWO"
B="$OUT/bundled"
uvx --quiet copier copy --quiet --defaults --vcs-ref v1 --data issues_repo=acme/tasks "$S" "$B"
bundled_like_two_layers() {
  diff -rq --exclude '.copier-answers.*' "$TWO" "$B" | sed 's/^/FAIL /' &&
    [ "$(cd "$B" && ls -d .copier-answers.*)" = .copier-answers.stack.yaml ] &&
    grep -qx 'issues_repo: acme/tasks' "$B/.copier-answers.stack.yaml" && grep -qx 'package_name: app' "$B/.copier-answers.stack.yaml"
}
expect "a copy of a stack template that bundles this one gives the two layers' files, with one answers file" bundled_like_two_layers
help_lists_each_layer() {  # each target of make help, after the file it is listed under
  local owners
  owners="$(cd "$B" && make -s | awk '/^[^ ]/ { f = $0 } /^  / { print f, $1 }')"
  [ "$owners" = "$(printf '%s\n' 'Makefile run' 'stack.mk gate' '.claude/agentic.mk help' '.claude/agentic.mk claude')" ] ||
    { printf 'FAIL make help listed:\n%s\n' "$owners"; return 1; }
}
expect "in the copy, bare make lists the targets of its Makefile, the stack fragment and this template's, each under its file" help_lists_each_layer
SI="$OUT/stand-ins"
mkdir -p "$SI/claude" "$SI/caffeinate"
cat >"$SI/claude/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
EOF
cat >"$SI/caffeinate/caffeinate" <<'EOF'
#!/bin/sh
echo "caffeinate $1"
shift
exec "$@"
EOF
chmod +x "$SI/claude/claude" "$SI/caffeinate/caffeinate"
MAKE_BIN="$(command -v make)"
make_claude() {  # make_claude <PATH> <expected output> <make arguments...>; the stand-ins print what ran
  local out
  out="$(cd "$B" && PATH="$1" "$MAKE_BIN" -s claude "${@:3}")" && [ "$out" = "$2" ] ||
    { printf 'FAIL make claude ran:\n%s\n' "$out"; return 1; }
}
expect "make claude keeps the machine awake and gives claude its flag, args and the prompt as one argument" make_claude \
  "$SI/caffeinate:$SI/claude:$PATH" "$(printf '%s\n' 'caffeinate -is' --remote-control --continue -- '/loop check the board; then stop')" \
  args=--continue 'prompt=/loop check the board; then stop'
expect "with no caffeinate and no prompt, make claude starts claude alone, with no empty argument" make_claude \
  "$SI/claude" --remote-control
git -C "$B" init -q
git -C "$B" add -A
git -C "$B" -c user.name=t -c user.email=t@t commit -qm copy
(cd "$B" && uvx --quiet copier update --quiet --defaults -a .copier-answers.stack.yaml --vcs-ref v2)
expect "copier update across a bundled release delivers this template's change, without --trust" bash -c "
  [ -f '$B/update-probe.txt' ] && [ ! -e '$B/.claude/skills/commit/SKILL.md' ] && grep -qx '_commit: v2' '$B/.copier-answers.stack.yaml'"
expect "the update keeps the files both layers seed once" bash -c "
  cmp -s '$OUT/src/template/renovate.json' '$B/renovate.json' && cmp -s '$OUT/src/tests/stack/template/Makefile' '$B/Makefile'"
expect "bundle.sh --check passes the stack template's bundle of its own version" bash "$NEXT/bundle.sh" --check "$S"
expect "bundle.sh --check fails the stack template's bundle of another version" bash -c "! bash '$OUT/src/bundle.sh' --check '$S'"
expect "bundle.sh refuses a stack template that has its own copy of a file it bundles" bash -c "
  mkdir -p '$OUT/clash/template' && cp '$OUT/src/template/renovate.json' '$OUT/clash/template/' && ! bash '$OUT/src/bundle.sh' '$OUT/clash'"

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
