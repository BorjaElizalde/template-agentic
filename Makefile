include .claude/agentic.mk

.PHONY: gate render
gate: ## Render the template the way a project gets it, then run every rendered suite.
	@bash tests/render-and-test.sh

OWNED := --exclude /memory/ --exclude /agent-memory/ --exclude /settings.local.json

render: ## Make .claude/, except the paths this repository owns, and the template's workflows match a render of the working tree.
	@. .claude/agentic.conf && tmp="$$(mktemp -d)" && trap 'rm -rf "$$tmp"' EXIT && \
	  mkdir "$$tmp/src" && tar --exclude .git -cf - . | tar -xf - -C "$$tmp/src" && \
	  uvx --quiet copier copy --quiet --defaults --data "issues_repo=$$ISSUES_REPO" \
	    --data "worktree_root=$$WORKTREE_ROOT" --data "deploy_workflow=$$DEPLOY_WORKFLOW" \
	    --data "agent_merges=$${AGENT_MERGES:-false}" \
	    "$$tmp/src" "$$tmp/out" && \
	  rsync -a --delete $(OWNED) "$$tmp/out/.claude/" .claude/ && \
	  cp "$$tmp/out/.github/workflows/"*.yaml .github/workflows/
