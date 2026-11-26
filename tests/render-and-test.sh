#!/usr/bin/env bash
# Renders the template and runs the rendered harness's own tests, the way a project gets it.
# Needs uv, git, jq and tmux.
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
  else echo "FAIL $1"; awk '/FAIL|rror/ && n++ < 20 { print "    " $0 }' <<<"$out"; fail=1; fi
}
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }
# A new bash, with this file's options: below expect's if, bash ignores set -e, in subshells too.
goes_on_after_a_silent_failure() {
  [ "$(bash -euo pipefail -c "$(declare -f expect); fail=0; expect silent false; expect next true; echo fail=\$fail")" = \
    "$(printf '%s\n' 'FAIL silent' 'PASS next' 'fail=1')" ]
}
expect "a failed check whose output has no FAIL or error line is reported, and the checks after it still run" \
  goes_on_after_a_silent_failure

D="$OUT/project"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks "$OUT/src" "$D"
git -C "$D" init -q
commit "$D" render

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
expect "with agent_merges the pull-request skill merges a pinned squash" \
  grep -qF 'gh pr merge <n> --squash --match-head-commit <sha>' "$AM/.claude/skills/pull-request/SKILL.md"
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
# Only /task:finish closes an issue, only task.sh park runs gh label; delete and transfer are final.
expect "settings.json allows gh issue create, list, view, comment and edit, and no other gh issue or gh label call" jq -e '
  [.permissions.allow[] | select(startswith("Bash(gh issue") or startswith("Bash(gh label"))] | sort
  == ["Bash(gh issue comment:*)", "Bash(gh issue create:*)", "Bash(gh issue edit:*)", "Bash(gh issue list:*)", "Bash(gh issue view:*)"]' \
  "$D/.claude/settings.json"
GATE="$D/.github/workflows/gate.yaml"
BRANCH_PROTECTION="$D/.github/workflows/branch-protection.yaml"
expect "the Gate and Branch protection workflows are valid workflows" uvx --quiet check-jsonschema --builtin-schema vendor.github-workflows \
  "$GATE" "$BRANCH_PROTECTION"
expect "the Gate workflow calls the stack's checks, never make" bash -c "
  [ \"\$(uvx --quiet yq -r '.jobs.gate.uses' '$GATE')\" = ./.github/workflows/gate-checks.yaml ] &&
  ! grep -v '^[[:space:]]*#' '$GATE' | grep -qw make"
# A skipped job that calls a workflow reports only as gate, never as the gate / <job> a ruleset requires.
expect "the Gate workflow skips a draft through the checks' skip input, and runs when one is marked ready" bash -c "
  grep -qx '    types: \[opened, synchronize, reopened, ready_for_review\]' '$GATE' &&
  [ \"\$(uvx --quiet yq -r '.jobs.gate.if' '$GATE')\" = null ] &&
  [ \"\$(uvx --quiet yq -r '.jobs.gate.needs' '$GATE')\" = read-draft ] &&
  uvx --quiet yq -r '.jobs.gate.with.skip' '$GATE' | grep -qF '\${{ needs.read-draft.outputs.draft'"
# A stub gh that says PR 7 of acme/app is a draft, and fails on any other call.
READ_DRAFT="$OUT/read-draft"
mkdir -p "$READ_DRAFT/bin"
cat >"$READ_DRAFT/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "api repos/acme/app/pulls/7 --jq .draft" ] && echo true
EOF
chmod +x "$READ_DRAFT/bin/gh"
reads_the_draft() {
  { echo '#!/usr/bin/env bash'; uvx --quiet yq -r '.jobs["read-draft"].steps[0].run' "$GATE"; } >"$READ_DRAFT/step.sh"
  GITHUB_REPOSITORY=acme/app PR=7 GITHUB_OUTPUT="$READ_DRAFT/output" PATH="$READ_DRAFT/bin:$PATH" \
    bash -e "$READ_DRAFT/step.sh" && [ "$(cat "$READ_DRAFT/output")" = draft=true ] &&
    [ "$(uvx --quiet yq -r '.jobs["read-draft"].outputs.draft' "$GATE")" = "\${{ steps.read.outputs.draft }}" ]
}
expect "read-draft reads from GitHub whether the PR is a draft as the run starts, and gives it as its output draft" reads_the_draft
PI="$OUT/paths-ignore"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks --data 'gate_paths_ignore={"**.md": "no check reads Markdown", ".claude/**": "no check reads the agent setup"}' "$OUT/src" "$PI"
expect "a gate_paths_ignore answer becomes the Gate workflow's paths-ignore, each pattern with its reason, in a valid workflow" bash -c "
  uvx --quiet check-jsonschema --builtin-schema vendor.github-workflows '$PI/.github/workflows/gate.yaml' &&
  [ \"\$(uvx --quiet yq -c '.on.pull_request[\"paths-ignore\"]' '$PI/.github/workflows/gate.yaml')\" = '[\"**.md\",\".claude/**\"]' ] &&
  grep -qxF '      - \"**.md\"  # no check reads Markdown' '$PI/.github/workflows/gate.yaml'"
expect "the Branch protection job reports as branch-protection on a PR into staging or main, and as up-to-date otherwise" bash -c "
  [ \"\$(uvx --quiet yq -r '.jobs[\"branch-protection\"].name' '$BRANCH_PROTECTION')\" = \
    \"\\\${{ github.event_name == 'pull_request' && github.base_ref != 'develop' && 'branch-protection' || 'up-to-date' }}\" ]"
# A stub gh: the open PRs' heads are a, b and d, b lacks two of develop's commits, d has its failed
# status, statuses are logged.
export UP_TO_DATE="$OUT/up-to-date"
mkdir -p "$UP_TO_DATE/bin"
for step in 1 2; do
  { echo '#!/usr/bin/env bash'; uvx --quiet yq -r ".jobs[\"branch-protection\"].steps[$step].run" "$BRANCH_PROTECTION"; } >"$UP_TO_DATE/step$step.sh"
done
cat >"$UP_TO_DATE/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "pr list --repo acme/app --base develop "*) printf 'a\nb\nd\n' ;;
  "api repos/acme/app/compare/develop...a --jq .behind_by") echo 0 ;;
  "api repos/acme/app/compare/develop...b --jq .behind_by") echo 2 ;;
  "api repos/acme/app/commits/d/status --jq "*) jq -n '{statuses: [{context: "up-to-date"}]}' | jq "${@: -1}" ;;
  "api repos/acme/app/commits/"*) jq -n '{statuses: [{context: "gate"}]}' | jq "${@: -1}" ;;
  "api repos/acme/app/statuses/"*) echo "$*" >>"$UP_TO_DATE/statuses" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$UP_TO_DATE/bin/gh"
up_to_date() {  # up_to_date <step> [<head>]: that step's script; what it prints lands in $UP_TO_DATE/out
  GITHUB_REPOSITORY=acme/app HEAD_SHA="${2:-}" PATH="$UP_TO_DATE/bin:$PATH" bash -e "$UP_TO_DATE/step$1.sh" >"$UP_TO_DATE/out" 2>&1
}
expect "a PR into develop whose head holds develop's commits passes up-to-date" up_to_date 1 a
fails_a_stale_pr() { ! up_to_date 1 b && grep -q "^::error::This branch lacks develop's newest commits (2)" "$UP_TO_DATE/out"; }
expect "a PR into develop whose head lacks develop's commits fails up-to-date, and is told to merge develop" fails_a_stale_pr
marks_the_stale_prs() {
  up_to_date 2 && [ "$(wc -l <"$UP_TO_DATE/statuses")" -eq 1 ] &&
    grep -q '^api repos/acme/app/statuses/b .*-f state=failure -f context=up-to-date ' "$UP_TO_DATE/statuses"
}
expect "a push to develop puts a failed up-to-date status on the head of each open PR that lacks its commits, once" marks_the_stale_prs
expect "both preset files and every renovate.json are valid Renovate config" uvx --quiet check-jsonschema \
  --schemafile https://docs.renovatebot.com/renovate-schema.json \
  "$ROOT/renovate/base.json" "$ROOT/renovate/default.json" "$ROOT/renovate.json" "$D/renovate.json"
# "$schema" is a JSON key, not a shell variable. Tried double quotes, but then each " and $ of the
# program needs a backslash.
# shellcheck disable=SC2016
expect "the project's renovate.json is the pointer to the project preset only" jq -e '
  keys == ["$schema", "description", "extends"]
  and .extends == ["github>BorjaElizalde/template-agentic//renovate/default"]' "$D/renovate.json"
expect "the project preset is the shared rules, with Renovate off the template's CI files" jq -e '
  .extends == ["github>BorjaElizalde/template-agentic//renovate/base"]
  and (.["github-actions"].ignorePaths | index(".github/workflows/gate-checks.yaml") != null)' \
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
expect "shellcheck finds nothing in any script" bash -c "set -o pipefail; find '$D' '$UP_TO_DATE' '$ROOT/tests' '$ROOT/bundle.sh' '$ROOT/release.sh' -name '*.sh' -exec uvx --quiet --from shellcheck-py==0.11.0.1 shellcheck --format gcc {} + | sed 's/^/FAIL /'"
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
expect "the task skills, the session files and pull-request name the issues repo" bash -c "
  grep -q 'gh issue create -R acme/tasks' '$D/.claude/skills/task/skills/start/SKILL.md' &&
  grep -q 'gh issue close <n> -R acme/tasks' '$D/.claude/skills/task/skills/finish/SKILL.md' &&
  grep -qF acme/tasks '$D/.claude/skills/task/session/prompt.md' &&
  for file in task/skills/status/SKILL.md task/session/execution.md pull-request/SKILL.md; do
    grep -qF 'gh issue view <n> -R acme/tasks --json title,body,comments' \"$D/.claude/skills/\$file\" || exit 1
  done"
expect "the execution session posts its plan with task.sh plan, which task.sh has" bash -c "
  grep -qF 'bash .claude/skills/task/scripts/task.sh plan <n> <file>' '$D/.claude/skills/task/session/execution.md' &&
  grep -qF '| plan <issue> <file> |' '$D/.claude/skills/task/scripts/task.sh'"
for reviewer in plan-reviewer readability-reviewer; do
  expect "$reviewer first reads the issue without the plan, the plan review and its reply, by their exact headings" bash -c "
    grep -qx \"PLAN_HEADING='## Plan'\" '$D/.claude/skills/task/scripts/task.sh' &&
    grep -qF '\`## Plan review\`' '$D/.claude/agents/plan-reviewer.md' &&
    grep -qF '\`## Plan review reply\`' '$D/.claude/skills/task/session/execution.md' &&
    grep -qF 'test(\"^## Plan( review( reply)?)?\\n\")' '$D/.claude/agents/$reviewer.md'"
done
expect "the rules hold the Readable code section that readability-reviewer names" bash -c "
  grep -qx '## Readable code' '$D/.claude/rules/conventions.md' &&
  grep -qF 'Your yardstick is \"Readable code\"' '$D/.claude/agents/readability-reviewer.md'"
expect "the issue, plan, PR and commit steps each send the agent to .claude/rules/writing.md, which the project has" bash -c "
  [ -f '$D/.claude/rules/writing.md' ] &&
  for step in task/skills/start/SKILL.md task/session/execution.md pull-request/SKILL.md commit/SKILL.md; do
    grep -qF '\`.claude/rules/writing.md\`' \"$D/.claude/skills/\$step\" || exit 1
  done"
for agent in "$D"/.claude/agents/*.md; do
  name="$(basename "$agent" .md)"
  expect "the execution session names $name, which has no tool that edits, nor memory, which adds Write and Edit" bash -c "
    grep -qF '\`$name\`' '$D/.claude/skills/task/session/execution.md' &&
    grep -q '^tools: Read' '$agent' && ! grep -qE '^(tools:.*(Edit|Write|Agent)|memory:)' '$agent'"
done
expect "no release facts file; without a deploy, release waits for none" bash -c "[ ! -e '$D/.claude/release.md' ] && ! grep -q 'await-run.sh' '$D/.claude/skills/release/SKILL.md'"
expect "session files sit only in the task plugin" bash -c "[ -z \"\$(find '$D/.claude' -maxdepth 1 -name 'subagent-session-*')\" ] && jq empty '$D/.claude/skills/task/session/settings.json'"

# S is the stack template's repository, whose main holds no bundle.
S="$OUT/stack"
cp -R "$OUT/src/tests/stack" "$S"
git -C "$S" init -q -b main
commit "$S" 'Add the stack template'
build() {  # build <tag> <copy of this template>: what the stack template's Build does on a merge to main
  rm -rf "$OUT/build"
  git clone --quiet --depth 1 --branch main "file://$S" "$OUT/build"
  (cd "$OUT/build" && git config user.name t && git config user.email t@t && bash "$2/release.sh" "$1")
}
build v1 "$OUT/src"
NEXT="$OUT/next"
cp -R "$OUT/src" "$NEXT"
printf 'probe\n' >"$NEXT/template/update-probe.txt"
rm "$NEXT/template/.claude/skills/commit/SKILL.md"
printf '{}\n' >"$NEXT/template/renovate.json"
printf 'gate:\n\t@echo v2\n' >"$S/template/Makefile"
commit "$S" 'Change the seeded Makefile'
build v2 "$NEXT"
parents_are() {  # parents_are <release> <commit...>: the release's parents are those commits, in order
  [ "$(git -C "$S" rev-parse "$1^@")" = "$(git -C "$S" rev-parse "${@:2}")" ]
}
expect "the first release's only parent is main as it was built on" parents_are v1 main^
expect "a later release's parents are main and the release before it" parents_are v2 main v1
expect "no branch holds a release" bash -c "[ -z \"\$(git -C '$S' branch --contains v1; git -C '$S' branch --contains v2)\" ]"

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
# Stand-ins for the programs make claude runs. claude and tmux print their arguments, then each of
# make's variables in their environment: make's own, and args and prompt from its command line.
SI="$OUT/stand-ins"
mkdir -p "$SI/claude" "$SI/caffeinate" "$SI/tmux" "$SI/env"
cat >"$SI/claude/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
export -p | while read -r _ var; do case $var in MAKE*|MFLAGS=*|args=*|prompt=*) echo "$var" ;; esac; done
EOF
cat >"$SI/caffeinate/caffeinate" <<'EOF'
#!/bin/sh
echo "caffeinate $1"
shift
exec "$@"
EOF
cat >"$SI/tmux/tmux" <<'EOF'
#!/bin/sh
echo tmux
printf '%s\n' "$@"
export -p | while read -r _ var; do case $var in MAKE*|MFLAGS=*|args=*|prompt=*) echo "$var" ;; esac; done
EOF
chmod +x "$SI/claude/claude" "$SI/caffeinate/caffeinate" "$SI/tmux/tmux"
ln -s "$(command -v env)" "$SI/env/"  # the env that make claude runs, on a PATH with no caffeinate
MAKE_BIN="$(command -v make)"
APP="$OUT/my.app"  # a copy of the project in a folder with a dot in its name
cp -R "$B" "$APP"
make_claude() {  # make_claude <TMUX> <PATH> <expected output> <make arguments...>; the stand-ins print what ran
  local out
  out="$(cd "$APP" && TMUX="$1" PATH="$2" "$MAKE_BIN" -s claude "${@:4}")" && [ "$out" = "$3" ] ||
    { printf 'FAIL make claude ran:\n%s\n' "$out"; return 1; }
}
IN_ITS_TMUX=/tmp/tmux-1000/my.app,1,0  # TMUX in a window of the project's own tmux server
expect "inside its own tmux, make claude keeps the machine awake and gives claude its flag, args and the prompt as one argument, and none of make's variables" make_claude \
  "$IN_ITS_TMUX" "$SI/caffeinate:$SI/claude:$PATH" \
  "$(printf '%s\n' 'caffeinate -is' --remote-control --continue -- '/loop check the board; then stop')" \
  args=--continue 'prompt=/loop check the board; then stop'
expect "with no caffeinate and no prompt, make claude starts claude alone, with no empty argument" make_claude \
  "$IN_ITS_TMUX" "$SI/env:$SI/claude" --remote-control
STARTS_ITS_TMUX="$(printf '%s\n' tmux -L my.app source-file .claude/tmux.conf ';' new-session -A -s my_app -n main \
  caffeinate -is claude --remote-control --continue -- '/loop check the board; then stop')"
expect "outside tmux, make claude starts the repository's tmux, named after its folder, with tmux.conf and none of make's variables, and claude kept awake in its main window, or attaches to it" \
  make_claude '' "$SI/tmux:$SI/caffeinate:$SI/claude:$PATH" "$STARTS_ITS_TMUX" \
  args=--continue 'prompt=/loop check the board; then stop'
expect "inside another tmux, make claude starts the repository's tmux all the same" \
  make_claude /tmp/tmux-1000/default,1,0 "$SI/tmux:$SI/caffeinate:$SI/claude:$PATH" "$STARTS_ITS_TMUX" \
  args=--continue 'prompt=/loop check the board; then stop'
loads_tmux_conf() {  # the project's tmux.conf, loaded twice into a tmux server of its own
  local socket="$OUT/tmux" ok=0
  tmux -S "$socket" -f /dev/null new-session -d \; source-file "$D/.claude/tmux.conf" \; source-file "$D/.claude/tmux.conf" &&
    [ "$(tmux -S "$socket" show -sv extended-keys)" = on ] &&
    [ "$(tmux -S "$socket" show -sv terminal-features | grep -cxF 'xterm*:extkeys')" -eq 1 ] &&
    [ "$(tmux -S "$socket" show -sv escape-time)" -eq 10 ] || ok=1
  tmux -S "$socket" kill-server
  return "$ok"
}
expect "tmux.conf turns extended keys on, for xterm terminals once however often it loads, and passes Esc on at once" loads_tmux_conf
git -C "$B" init -q
commit "$B" copy
(cd "$B" && uvx --quiet copier update --quiet --defaults -a .copier-answers.stack.yaml --vcs-ref v2)
expect "copier update across a bundled release delivers this template's change, without --trust" bash -c "
  [ -f '$B/update-probe.txt' ] && [ ! -e '$B/.claude/skills/commit/SKILL.md' ] && grep -qx '_commit: v2' '$B/.copier-answers.stack.yaml'"
expect "the update keeps the files both layers seed once" bash -c "
  cmp -s '$OUT/src/template/renovate.json' '$B/renovate.json' && cmp -s '$OUT/src/tests/stack/template/Makefile' '$B/Makefile'"
expect "bundle.sh refuses a stack template that has its own copy of a file it bundles" bash -c "
  mkdir -p '$OUT/clash/template' && cp '$OUT/src/template/renovate.json' '$OUT/clash/template/' && ! bash '$OUT/src/bundle.sh' '$OUT/clash'"

# This repository is a project of its own template: on a copy of the working tree, make render
# (which the pre-commit hook runs on every commit that changes template/) must leave .claude/ and
# .github/ as they are.
mkdir -p "$OUT/self"
(cd "$ROOT" && tar --exclude .git -cf - .) | tar -xf - -C "$OUT/self"
harness_in_step() {
  local drift
  make -s -C "$OUT/self" render >/dev/null || return 1
  drift="$(diff -rq "$ROOT/.claude" "$OUT/self/.claude"; diff -rq "$ROOT/.github" "$OUT/self/.github")"
  [ -n "$drift" ] || return 0
  sed "s#$OUT/self#render#g; s#$ROOT#repository#g; s/^/FAIL /" <<<"$drift"
  return 1
}
expect "this repository's harness and workflows are in step with the template (make render changes nothing)" harness_in_step

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
