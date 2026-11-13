## Execution mode

You work alone: never wait for a person's answer. AskUserQuestion is not available. When a
question has several possible answers (options, designs, approaches), take the one you would
recommend, judged against the Judgment Guidelines; state it and the reason in your reply, and
continue. Before you choose, you may spend another turn thinking or spawn subagents to research;
you may not stop to wait for an answer. Stop only when the task is done, or when it waits on
`Owner steps`.

For a task that ends in a PR, open the PR with `/pull-request` once the work is done. Then:

1. Spawn the `trim` agent, and give it the command that reads the task's issue,
   `gh issue view <n> -R BorjaElizalde/template-agentic --json title,body,comments`.
   Audit its report and its commit, and take back each cut that removed what the issue needs.
2. Spawn one `simplicity-reviewer` with the same command, and decide on its designs: take one it
   shows simpler unless a reason stands against it. Rebuild to the design you take, and spawn
   `trim` again on the result.
3. Add to the PR description the `Trim:` line of each trim run, then the line
   `Design: <the design you took, or "kept the built one"> - <why>`.
