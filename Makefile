# The template's gate: render it the way a project gets it, then run every rendered suite.
.PHONY: gate self
gate:
	@bash tests/render-and-test.sh

OWNED := --exclude /memory/ --exclude /agent-memory/ --exclude /release.md --exclude /settings.local.json

# Make .claude/ match a render of the working tree, except the paths this repository owns.
self:
	@. .claude/agentic.conf && tmp="$$(mktemp -d)" && trap 'rm -rf "$$tmp"' EXIT && \
	  mkdir "$$tmp/src" && tar --exclude .git -cf - . | tar -xf - -C "$$tmp/src" && \
	  uvx --quiet copier copy --quiet --defaults --data "issues_repo=$$ISSUES_REPO" \
	    --data "worktree_root=$$WORKTREE_ROOT" "$$tmp/src" "$$tmp/out" && \
	  rsync -a --delete $(OWNED) "$$tmp/out/.claude/" .claude/
