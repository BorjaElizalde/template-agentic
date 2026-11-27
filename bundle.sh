#!/usr/bin/env bash
# Bundles this checkout of template-agentic into a stack template's tree that holds no earlier
# bundle. Run from a clone at the version:
#   bash bundle.sh <stack-template>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

listing() { (cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort); }

clash="$(listing "$1/template" | LC_ALL=C comm -12 - <(listing "$ROOT/template"))"
[ -z "$clash" ] || { printf 'The stack template has its own copy of files this template bundles:\n%s\n' "$clash" >&2; exit 1; }
cp -R "$ROOT/template/." "$1/template/"
mkdir -p "$1/agentic"
cp "$ROOT/copier.yaml" "$1/agentic/copier.yaml"
