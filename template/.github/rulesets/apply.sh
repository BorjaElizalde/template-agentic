#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Makes this repository's GitHub rulesets match the files beside it, one ruleset per file, found
# by its name: creates each missing one and replaces each one that differs. Prints each ruleset's
# state, with a diff where it differs, and names each ruleset that no file holds: it still binds
# its branch, and only the owner removes it. With --check it changes nothing, and fails when a
# ruleset does not match. Needs gh logged in as an admin of the repository, and develop, staging
# and main pushed first: a ruleset that requires checks refuses the push that creates its branch.
#   bash .github/rulesets/apply.sh [--check]    (make rulesets, make rulesets-check)
# When a template update changes these files, apply them on its branch right before it merges into
# develop, with no PR into staging or main open: gh pr checkout <n>, make rulesets, then merge. A
# PR reports the checks of the workflows in its merge commit, so before the update merges only its
# own PR reports the new checks, and after it, develop's ruleset makes every other PR merge develop.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
check=false
case "${1:-}" in
  '') ;;
  --check) check=true ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

# On a plan with no rulesets, GitHub refuses this first call, and gh prints GitHub's reason. An
# organization's rulesets are left out: this repository's settings can't change them.
ids="$(gh api 'repos/{owner}/{repo}/rulesets?includes_parents=false' --jq '.[].id')"
live=""
for id in $ids; do live+="$(gh api "repos/{owner}/{repo}/rulesets/$id")"; done

id_of() { jq -rs --arg name "$1" '.[] | select(.name == $name) | .id' <<<"$live"; }

stated_fields() {  # stated_fields <file>: of the live ruleset with the file's name, the fields the file states
  jq -s --slurpfile stated "$1" '.[] | select(.name == $stated[0].name)
    | with_entries(select(.key as $key | $stated[0] | has($key)))' <<<"$live"
}

unstated() {  # the names of the live rulesets that no file holds, one per line
  jq -rs --argjson stated "$(jq -s 'map(.name)' "$DIR"/*.json)" '.[].name | select(IN($stated[]) | not)' <<<"$live"
}

# Sorted arrays, so the order of the rules or of the checks is no difference.
normalized() { jq -S 'walk(if type == "array" then sort else . end)'; }

write() {  # write <file> [<id>]: creates the file's ruleset, or replaces the ruleset with that id
  if [ -z "$2" ]; then gh api -X POST 'repos/{owner}/{repo}/rulesets' --input "$1" --silent
  else gh api -X PUT "repos/{owner}/{repo}/rulesets/$2" --input "$1" --silent; fi
}

mismatched=false
for file in "$DIR"/*.json; do
  name="$(jq -r .name "$file")"
  id="$(id_of "$name")"
  if [ -z "$id" ]; then
    echo "$name: missing"
  elif changes="$(diff -u --label "$(basename "$file")" --label GitHub \
    <(normalized <"$file") <(stated_fields "$file" | normalized))"; then
    echo "$name: matches"
    continue
  else
    printf '%s: differs\n%s\n' "$name" "$changes"
  fi
  mismatched=true
  if ! $check; then
    write "$file" "$id"
    echo "$name: applied"
  fi
done
while IFS= read -r name; do
  echo "$name: not in .github/rulesets/"
  mismatched=true
done < <(unstated)
if $check && $mismatched; then exit 1; fi
