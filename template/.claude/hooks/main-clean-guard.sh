#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# PostToolUse(Bash) main-clean guard — language-agnostic: worktree-guard.sh sees only the Edit and
# Write tools, so a script that saves by relative path, or a shell redirect, changes the main
# checkout unseen until bash-guard.sh blocks a commit there. After a Bash call whose working
# directory is a main checkout (git-dir equals git-common-dir, as in worktree-guard.sh), this names
# the checkout's untracked files that are not ignored and its changed tracked files to Claude.
# Exit 2 is the mechanism: it is the only code whose stderr reaches Claude.
# Each change is named once. The status last seen is kept in the git dir, so a file the owner
# keeps there is named once, not after every call, and a file removed and made again is named again.
# --no-optional-locks keeps status from taking the index lock that a concurrent git command needs.
# Fails OPEN (exit 0): a linked worktree, no repository, or git can't answer.
set -u

DIR="$(jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$DIR" ] || exit 0
GD="$(git -C "$DIR" rev-parse --absolute-git-dir 2>/dev/null || true)"
CD="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[ -n "$GD" ] && [ "$GD" = "$CD" ] || exit 0

NOW="$(git -C "$DIR" --no-optional-locks status --porcelain 2>/dev/null)" || exit 0
SEEN="$GD/main-clean-guard.seen"
[ -n "$NOW" ] || { rm -f "$SEEN"; exit 0; }
NEW="$(comm -13 <(sort "$SEEN" 2>/dev/null) <(sort <<<"$NOW"))"
printf '%s\n' "$NOW" >"$SEEN"
[ -n "$NEW" ] || exit 0

{
  echo "New changes in the main checkout ($(git -C "$DIR" rev-parse --show-toplevel)), where no work belongs:"
  sed 's/^/  /' <<<"$NEW"
  echo "For each change this session made: move the work into the task's worktree, delete it if it"
  echo "is scratch (git restore a changed tracked file), or gitignore a file that belongs there."
  echo "Leave a change you did not make: it is the owner's. Each change is named once."
} >&2
exit 2
