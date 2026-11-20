#!/usr/bin/env bash
# Bundles this checkout of template-agentic into a stack template's tree that holds no earlier
# bundle: this template's files into its template/, and this template's copier.yaml to the
# agentic/copier.yaml its copier.yaml includes. release.sh runs it; run from a clone at the version:
#   bash bundle.sh <stack-template>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

listing() { (cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort); }

clash="$(LC_ALL=C comm -12 <(listing "$1/template") <(listing "$ROOT/template"))"
[ -z "$clash" ] || { printf 'The stack template has its own copy of files this template bundles:\n%s\n' "$clash" >&2; exit 1; }
cp -R "$ROOT/template/." "$1/template/"
mkdir -p "$1/agentic"
cp "$ROOT/copier.yaml" "$1/agentic/copier.yaml"
