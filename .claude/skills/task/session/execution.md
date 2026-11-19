## Execution mode

You work alone: never wait for a person's answer. AskUserQuestion is not available. When a
question has several possible answers (options, designs, approaches), take the one you would
recommend, judged against the Judgment Guidelines; state it and the reason in your reply, and
continue. Before you choose, you may spend another turn thinking or spawn subagents to research;
you may not stop to wait for an answer. Stop only when the task is done, or when it waits on
`Owner steps`.

For a task that ends in a PR, plan before you build. Work out the smallest design that meets
everything the issue asks: hold each thing it adds against the Design Philosophy and questions 1
to 3 of `.claude/agents/code-trimmer.md`. Write the plan to a file, for a reader who has the issue
and not the code:

- what you will build, and where;
- each thing it adds, such as a file, a command, a setting or a name, with the reason the issue
  needs it;
- each choice between designs: the one you took, and why.

Post it with `bash .claude/skills/task/scripts/task.sh plan <n> <file>`, which makes it the
issue's one pinned comment, headed `Plan`. Then build: nobody answers a plan. A plan the issue
already has is the task's own, from an earlier session or from its session in another repository:
go on from it. When the design changes, post the plan again with the same command: the design as
it stands and, under `Changes`, what changed and why. Once the PR is open, say the change in its
body too.

Open that PR with `/pull-request` once the work is done. Then
run the steps below, and give each agent the command that reads the task's issue,
`gh issue view <n> -R BorjaElizalde/template-agentic --json title,body,comments`.
Skip steps 1 and 3 when the change is small, a bug fix or a small extension. Judge that by what
the change does, not by its line count: a mirrored copy doubles the count, and a wide mechanical
rename is large but low risk.

1. Spawn the `code-reviewer` agent. Fix each **Must change** finding, and each **Optional** one
   unless a reason stands against it, then push.
2. Spawn the `code-trimmer` agent. Audit its report and its commit, and take back each cut that
   removed what the issue needs.
3. Spawn one `simplicity-reviewer`, and decide on its designs: take one it shows simpler unless a
   reason stands against it. Rebuild to the design you take, a change of the plan, and push it.
   When the rebuild adds code, run steps 1 and 2 again on the result; a line it only shortens or
   rewraps adds none.
