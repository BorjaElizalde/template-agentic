# From the agentic template: change the template, not this copy.
# make claude starts Claude, and make help lists the described targets of the project's Makefile
# and of every fragment it includes. The project's Makefile, or the stack template's fragment it
# includes, includes this file. A project extends it with its own targets, prerequisites and
# variables set after the include, never with a second recipe for a target here.
.DEFAULT_GOAL := help

# Claude Code keeps a Mac awake only while a session is busy, and never against system sleep.
KEEP_AWAKE ?= $(if $(shell command -v caffeinate),caffeinate -is)
CLAUDE_FLAGS ?= --remote-control

.PHONY: help claude
help: ## List every target, under the file that defines it.
	@awk -F ':.*## ' '/^[a-zA-Z0-9_-]+:.*## / { if (FILENAME != f) { f = FILENAME; printf "\n%s\n", f } printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# make exports a variable given on its command line, so the shell passes the prompt as one argument.
claude: ## Start Claude with Remote Control and keep the machine awake: args="--continue" prompt="/loop ..."
	@$(KEEP_AWAKE) claude $(CLAUDE_FLAGS) $(args) $${prompt:+"$$prompt"}
