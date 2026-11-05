# The template's gate: render it the way a project gets it, then run every rendered suite.
.PHONY: gate
gate:
	@bash tests/render-and-test.sh
