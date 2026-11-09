#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Runs the project's own hooks: settings.json calls `project.sh <event>`, and this runs every file
# in .claude/hooks/project/<event>/ in name order, each with the hook payload on stdin. That folder
# is the project's; the template never writes into it. Each file is a program its shebang runs.
# The contract is a command hook's, with one hook's stderr per script:
#   * stdout passes through (on SessionStart and UserPromptSubmit it becomes context);
#   * the first script that exits 2 stops the run, its stderr is the reason, and this exits 2;
#   * a script that fails any other way is reported on one stderr line that names it, the rest
#     still run, so a later script can still block, and this exits 1;
#   * a script's stderr on exit 0 is dropped, as Claude Code drops it.
# JSON output is not supported: several scripts' JSON can't be merged into one answer.
set -u
dir="$(cd "$(dirname "$0")" && pwd)/project/$1"
[ -d "$dir" ] || exit 0
payload="$(cat)"
status=0
shopt -s nullglob
exec 3>&1
for script in "$dir"/*; do
  err="$("$script" <<<"$payload" 2>&1 >&3)"; code=$?
  case $code in
    0) ;;
    2) printf '%s\n' "$err" >&2; exit 2 ;;
    *) printf 'project hook %s/%s failed (exit %s)%s\n' "$1" "${script##*/}" "$code" "${err:+: $err}" >&2
       status=1 ;;
  esac
done
exit "$status"
