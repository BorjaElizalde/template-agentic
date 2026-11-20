#!/usr/bin/env bash
# Releases a stack template with this checkout of template-agentic inside: bundles this template
# into the checked-out main, commits the tree as a commit no branch holds, and pushes it as <tag>.
# The commit's second parent is the newest release on origin, so the compare of two releases shows
# only what changed. The stack template's Build runs it in its checkout of main, with a git
# identity, from a clone of this repository at the version .copier-answers.agentic.yaml records:
#   bash <clone>/release.sh <tag>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
tag="$1"

parents=(-p HEAD)
previous="$(git ls-remote --tags --refs --sort=-v:refname origin | sed -n '1s#.*refs/tags/##p')"
if [ -n "$previous" ]; then
  git fetch --quiet --depth 1 origin tag "$previous"
  parents+=(-p "$previous")
fi
bash "$ROOT/bundle.sh" .
# Forced: a release holds every bundled file, also one that the stack template's .gitignore matches.
git add --force -- agentic template
git tag "$tag" "$(git commit-tree "$(git write-tree)" "${parents[@]}" -m "Release $tag")"
git push --quiet origin "$tag"
