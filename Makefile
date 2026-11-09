# The template's gate: render it the way a project gets it, then run every rendered suite.
.PHONY: gate render
gate:
	@bash tests/render-and-test.sh

OWNED := --exclude /memory/ --exclude /agent-memory/ --exclude /settings.local.json

# Make .claude/ match a render of the working tree, except the paths this repository owns.
render:
	@. .claude/agentic.conf && tmp="$$(mktemp -d)" && trap 'rm -rf "$$tmp"' EXIT && \
	  mkdir "$$tmp/src" && tar --exclude .git -cf - . | tar -xf - -C "$$tmp/src" && \
	  uvx --quiet copier copy --quiet --defaults --data "issues_repo=$$ISSUES_REPO" \
	    --data "worktree_root=$$WORKTREE_ROOT" --data "deploy_workflow=$$DEPLOY_WORKFLOW" \
	    --data "agent_merges=$${AGENT_MERGES:-false}" --data "session_stop_check=$${SESSION_STOP_CHECK:-true}" \
	    "$$tmp/src" "$$tmp/out" && \
	  rsync -a --delete $(OWNED) "$$tmp/out/.claude/" .claude/
