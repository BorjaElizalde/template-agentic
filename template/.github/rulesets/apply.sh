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

# An organization's rulesets are left out: this repository's settings can't change them.
list_ids() { gh api 'repos/{owner}/{repo}/rulesets?includes_parents=false' --jq '.[].id'; }

# On a plan with no rulesets, GitHub refuses the list: "Upgrade to GitHub Pro or make this
# repository public to enable this feature."
ids="$(list_ids)" ||
  { echo "GitHub refused to list this repository's rulesets, for the reason above. Nothing changed." >&2; exit 1; }
live=""
for id in $ids; do live+="$(gh api "repos/{owner}/{repo}/rulesets/$id")"; done

id_of() { jq -rs --arg name "$1" '.[] | select(.name == $name) | .id' <<<"$live"; }

on_github() {  # on_github <file>: the live ruleset with the file's name, cut to the fields the file states
  jq -s --slurpfile stated "$1" '.[] | select(.name == $stated[0].name)
    | with_entries(select(.key as $key | $stated[0] | has($key)))' <<<"$live"
}

# Sorted arrays, so the order of the rules or of the checks is no difference.
normalized() { jq -S 'walk(if type == "array" then sort else . end)'; }

difference() {  # difference <file>: a diff of the file against its live ruleset, empty when they match
  diff -u --label "$(basename "$1")" --label GitHub <(normalized <"$1") <(on_github "$1" | normalized) || true
}

unstated() {  # the names of the live rulesets that no file holds, one per line
  jq -rs --argjson stated "$(jq -s 'map(.name)' "$DIR"/*.json)" '.[].name | select(IN($stated[]) | not)' <<<"$live"
}

create() {  # create <file>: the file's ruleset, on GitHub
  gh api -X POST 'repos/{owner}/{repo}/rulesets' --input "$1" --silent
  echo "$(jq -r .name "$1"): created"
}

replace() {  # replace <id> <file>: the live ruleset with that id, by the file's
  gh api -X PUT "repos/{owner}/{repo}/rulesets/$1" --input "$2" --silent
  echo "$(jq -r .name "$2"): replaced"
}

mismatched=false
for file in "$DIR"/*.json; do
  name="$(jq -r .name "$file")"
  id="$(id_of "$name")"
  changes="$(difference "$file")"
  if [ -z "$id" ]; then
    echo "$name: missing"
    mismatched=true
    $check || create "$file"
  elif [ -n "$changes" ]; then
    printf '%s: differs\n%s\n' "$name" "$changes"
    mismatched=true
    $check || replace "$id" "$file"
  else
    echo "$name: matches"
  fi
done
while IFS= read -r name; do
  echo "$name: not in .github/rulesets/"
  mismatched=true
done < <(unstated)
if $check && $mismatched; then exit 1; fi
