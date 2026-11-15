#!/usr/bin/env bash
# Bundles this checkout of template-agentic into a stack template, so a project applies the stack
# template alone: this template's template/ files go into the stack's template/, and its copier.yaml
# into agentic/copier.yaml, which the stack's copier.yaml includes. agentic/files lists the bundled
# files, so the next run removes the ones a later version drops. Run it from a clone at the version:
#   bash bundle.sh <stack-template>            bundle that version into the stack template
#   bash bundle.sh --check <stack-template>    fail when the stack's bundle differs from that version's
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

listing() { (cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort); }

bundle() {  # bundle <stack>
  local bundled="$1/agentic/files" clash f
  mkdir -p "$1/agentic"
  touch "$bundled"
  clash="$(listing "$1/template" | LC_ALL=C comm -23 - "$bundled" | LC_ALL=C comm -12 - <(listing "$ROOT/template"))"
  [ -z "$clash" ] || { printf 'The stack template has its own copy of files this template bundles:\n%s\n' "$clash" >&2; return 1; }
  while IFS= read -r f; do rm -f "$1/template/$f"; done <"$bundled"
  cp -R "$ROOT/template/." "$1/template/"
  listing "$ROOT/template" >"$bundled"
  cp "$ROOT/copier.yaml" "$1/agentic/copier.yaml"
}

check() {  # check <stack>: a fresh bundle into a copy of the stack's bundle changes nothing
  copy="$(mktemp -d)"
  trap 'rm -rf "$copy"' EXIT
  cp -R "$1/agentic" "$1/template" "$copy/"
  bundle "$copy"
  if ! { diff -rq "$1/agentic" "$copy/agentic" && diff -rq "$1/template" "$copy/template"; }; then
    echo "The bundle differs from this version's: run bash bundle.sh $1 from this clone" >&2
    return 1
  fi
}

if [ "${1:-}" = --check ]; then check "$2"; else bundle "$1"; fi
