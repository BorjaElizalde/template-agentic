#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
set -euo pipefail

usage="usage: scripts/issue.sh worktree <issue> [type] | open-session <issue> | close-session <issue> | point-memory"

cd "$(dirname "$0")/.."
CHECKOUT=$PWD
# Worktree paths resolve from the main checkout, the first entry git lists, even when this runs in
# a worktree. Its folder name names this repository's worktree inside each issue's folder, so a
# cross-repository task's worktrees sit side by side.
MAIN=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
REPO_NAME=$(basename "$MAIN")
cd "$MAIN"
. .claude/agentic.conf

die() {
	echo "$*" >&2
	exit 1
}

# The issue's title, cut at a word boundary to 40 characters.
issue_title() {
	gh issue view "$1" -R "$ISSUES_REPO" --json title -q .title |
		awk 'length > 40 { $0 = substr($0, 1, 41); sub(/ [^ ]*$/, "") } 1'
}

issue_worktree() {
	git worktree list --porcelain | awk -v issue="$1" '
		/^worktree / { worktree = substr($0, 10) }
		!found && $0 ~ "^branch refs/heads/[^/]+/" issue "-" { print worktree; found = 1 }
		END { exit !found }'
}

has_session_transcript() {
	ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"/*.jsonl >/dev/null 2>&1
}

# The tty of a claude process whose working directory is $1.
session_tty() {
	local pid tty
	while read -r pid tty; do
		if [ "$(lsof -a -p "$pid" -d cwd -Fn | sed -n 's/^n//p')" = "$1" ]; then
			echo "/dev/$tty"
			return
		fi
	done < <(ps -axo pid=,tty=,comm= | awk '$2 != "??" && $3 ~ /(^|\/)claude$/ { print $1, $2 }')
	return 1
}

# autoMemoryDirectory takes only an absolute or ~/ path, so each checkout's gitignored local
# settings point Claude at that checkout's own committed store.
point_memory() {
	local checkout=$1 settings=$1/.claude/settings.local.json
	[ -f "$settings" ] || printf '{}\n' >"$settings"
	jq --arg dir "$checkout/.claude/memory" '.autoMemoryDirectory = $dir' "$settings" >"$settings.tmp"
	mv "$settings.tmp" "$settings"
}

create_worktree() {
	local issue=$1 type=$2 slug branch worktree
	slug=$(issue_title "$issue" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
	branch=$type/$issue-$slug
	worktree=$WORKTREE_ROOT/$issue-$slug/$REPO_NAME
	git fetch origin develop -q
	mkdir -p "$(dirname "$worktree")"
	git worktree add -b "$branch" "$worktree" origin/develop
	worktree=$(cd "$worktree" && pwd)
	# Seed the gitignored files git worktree add can't carry, never overwriting one.
	cp -n .env* "$worktree"/ 2>/dev/null || true
	cp -n .claude/settings.local.json "$worktree/.claude/settings.local.json" 2>/dev/null || true
	point_memory "$worktree"
	echo "✓ worktree ready: $worktree (branch $branch, env + local settings seeded)"
}

open_session() {
	local issue=$1 worktree title resume=
	worktree=$(issue_worktree "$issue") || die "no worktree for issue $issue: run make worktree issue=$issue"
	title=$(issue_title "$issue")
	# claude --continue refuses to start where no session exists yet.
	if has_session_transcript "$worktree"; then resume=--continue; fi
	# exec: claude replaces the window's shell, so Terminal can close the window when claude exits.
	osascript - "$worktree" "#$issue $REPO_NAME: $title" "$resume" \
		"$PWD/.claude/subagent-session-settings.json" "$PWD/.claude/subagent-session-prompt.md" >/dev/null <<'APPLESCRIPT'
on run {worktree, sessionName, resumeFlag, settingsFile, promptFile}
	tell application "Terminal"
		do script "cd " & quoted form of worktree & " && exec claude " & resumeFlag & " --settings " & quoted form of settingsFile & " --append-system-prompt-file " & quoted form of promptFile & " --disallowed-tools AskUserQuestion -n " & quoted form of sessionName
		activate
	end tell
end run
APPLESCRIPT
}

close_session() {
	local issue=$1 worktree tty
	worktree=$(issue_worktree "$issue") || die "no worktree for issue $issue"
	tty=$(session_tty "$worktree") || die "no Claude session is running in $worktree"
	osascript - "$tty" <<'APPLESCRIPT'
on run {sessionTty}
	tell application "Terminal"
		-- claude sets the window title itself, so the tab is found by its tty.
		repeat with w in windows
			set windowTabs to {}
			-- Terminal can list a window whose tabs can't be read.
			try
				set windowTabs to tabs of w
			end try
			repeat with t in windowTabs
				if tty of t is sessionTty then
					-- do script ends the text with the carriage return that Enter sends.
					do script "/exit" in t
					return
				end if
			end repeat
		end repeat
	end tell
	error "no Terminal tab on " & sessionTty
end run
APPLESCRIPT
}

case ${1:-} in
worktree) [ $# -ge 2 ] || die "$usage"; create_worktree "$2" "${3:-feat}" ;;
open-session) [ $# -ge 2 ] || die "$usage"; open_session "$2" ;;
close-session) [ $# -ge 2 ] || die "$usage"; close_session "$2" ;;
point-memory) point_memory "$CHECKOUT" && echo "✓ auto memory points at $CHECKOUT/.claude/memory" ;;
*) die "$usage" ;;
esac
