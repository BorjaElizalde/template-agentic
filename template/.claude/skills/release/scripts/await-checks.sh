#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Poll one PR's checks until none are pending, then print each as "<bucket>\t<name>\t<link>".
# Checks register one by one, so name each check the PR must carry: a poll that falls between two
# of them sees none pending.
#   0  every check passed or was skipped
#   1  a check failed or was cancelled
#   2  usage, or checks still pending at the deadline
#   3  a named check, or with none named any check, never registered — the caller decides whether
#      that is correct for this PR
# Resumable: a run cut short mid-poll can simply be started again.
set -u -o pipefail

pr=${1:-}
[[ -n "$pr" ]] || { printf 'Usage: %s <pr-number> [<check>...]\n' "$0" >&2; exit 2; }

interval=30
grace=300     # a configured workflow registers its checks well inside 5 minutes
deadline=3600 # an hour covers a long build plus runner pickup and queueing
seen=0

while :; do
  checks=$(gh pr checks "$pr" --json name,bucket,link 2>/dev/null)

  if ! jq -e 'type == "array" and length > 0 and $ARGS.positional - map(.name) == []' \
    --args "${@:2}" <<<"${checks:-null}" >/dev/null 2>&1; then
    # A transient gh failure must never read as "this PR has no checks", so grace applies
    # only until the first sighting.
    if (( seen == 0 && SECONDS > grace )); then
      printf 'PR #%s has not registered its checks within %ss.\n' "$pr" "$grace"
      exit 3
    fi
  else
    seen=1
    if ! jq -e 'any(.[]; .bucket == "pending")' <<<"$checks" >/dev/null; then
      jq -r '.[] | "\(.bucket)\t\(.name)\t\(.link)"' <<<"$checks"
      jq -e 'any(.[]; .bucket == "fail" or .bucket == "cancel")' <<<"$checks" >/dev/null && exit 1
      exit 0
    fi
  fi

  if (( SECONDS > deadline )); then
    printf 'PR #%s still has pending checks after %ss.\n' "$pr" "$deadline"
    exit 2
  fi
  sleep "$interval"
done
