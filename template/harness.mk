# From the agentic template: change the template, not this copy.
# Every task is an issue; scripts/issue.sh creates the issue's worktree and opens or closes its
# Claude session, keyed by the issue number.
.PHONY: worktree claude claude_subagent_session close_claude_session point_memory

worktree:
	@scripts/issue.sh worktree $(issue) $(type)

# Start Claude here with Remote Control on; caffeinate keeps the Mac from idle-sleeping while it
# runs, so the session stays reachable from another device.
claude:
	@caffeinate -i claude --remote-control

claude_subagent_session:
	@scripts/issue.sh open-session $(issue)

close_claude_session:
	@scripts/issue.sh close-session $(issue)

# Run once per clone: worktrees get theirs from make worktree.
point_memory:
	@scripts/issue.sh point-memory
