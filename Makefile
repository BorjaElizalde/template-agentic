# The template's gate: render it the way a project gets it, then run every rendered suite.
.PHONY: gate self
gate:
	@bash tests/render-and-test.sh

# Re-render this repository's own harness; Copier's answers file names the temp source, so drop it.
self:
	@. .claude/agentic.conf && src="$$(mktemp -d)" && \
	  tar --exclude .git -cf - . | tar -xf - -C "$$src" && \
	  uvx --quiet copier copy --quiet --defaults --overwrite --data "issues_repo=$$ISSUES_REPO" \
	    --data "worktree_root=$$WORKTREE_ROOT" "$$src" . && \
	  rm -rf "$$src" .copier-answers.agentic.yaml
