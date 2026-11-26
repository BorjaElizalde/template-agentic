---
name: status
description: Use when the owner asks for the status of the tasks, in words or with /task:status, and in the first reply after a session start in the main checkout. Runs the cleanup and the status, acts on each task that needs it, and answers with one card per task, then the backlog's ready, blocked and parked issues.
allowed-tools: Bash(bash:*)
---

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task.sh" cleanup`, then
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task.sh" status`. The status lists every open issue once:
   one line per task under In progress, then the rest under Ready, Blocked and Parked.
2. Read each task's issue with `gh issue view <n> -R BorjaElizalde/template-agentic --json title,body,comments`,
   for its goal and any `Owner steps` comment, and the last message of each session that is idle or
   waiting.
3. A line that ends in `needs attention` asks for a move. Make it by the first case that fits, and
   give the task's card its mark:
   - a design task idle with a question in its last message: the question is the owner's, who
     answers it in its tmux window, `#<n>`. Never answer it for the owner, and never send the
     session back to work past it. ✋
   - idle, PR open and checks passed: review the PR; the owner merges it. 👀
   - checks failed: send the session back to work with SendMessage, saying what failed. ⏳
   - idle, PR open and gate not run: send the session back with SendMessage to mark the PR draft,
     then ready, which starts the gate on its head. ⏳
   - idle, PR draft: its review steps have not ended, and it marks the PR ready when they do.
     Send the session back to them with SendMessage. ⏳
   - idle, no PR, with a result to close the issue on in its last message: the owner reviews the
     result before you finish the task. 👀
   - idle, no PR, with a blocker or a question in its last message: make each choice it holds as
     **Choices** in `.claude/rules/agentic.md` says, and send the session what it needs to go on
     with SendMessage. ⏳ A choice that stays the owner's makes the mark 💬.
   - waiting: the owner answers it in its tmux window, `#<n>`. ✋
   - no session: resume it with `/task:start <n>`. ⏳

   `Owner steps` the owner has not taken yet make the mark ✋. Every other task is running: ⏳.
4. Reply in plain words: short sentences, the answer first, and no hashes, file paths or commands
   unless the owner needs one to act.
   - Open with one line: how many cards need the owner.
   - Then the legend: 👀 PR or result to review · ✋ your own step · 💬 your decision · ⏳ running.
   - Then one card per task, first those that need the owner, then the running ones:

     ```
     ### 👀 #n The task in plain words
     - **Goal:** one sentence.
     - **Now:** where it stands: the session, the PR and its checks, and each choice you made.
     - **You:** what the owner does, with your pick and the PR or issue link.
     ```

     **You** also carries the `Owner steps`, and each choice from the session's last message that
     stays the owner's. A running card has no **You**.
   - Then three lists, one line per issue, its number and what it is in plain words: **Ready**,
     **Blocked**, with the issues it waits on, and **Parked**, with the reason. The cards are for
     the tasks in progress only. Leave out a list with no issue, and give a list of more than ten
     issues its first ten, then how many more there are.
   - End with **Cleaned up**: each task a cleanup finished or refused to finish since your last
     status reply, and why. A task whose issue is closed gets no card: it shows only here.
