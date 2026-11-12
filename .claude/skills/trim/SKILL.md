---
name: trim
description: Use once an execution task's work is done and `/gate` is green, before its PR. Removes in counted rounds what the task did not need.
---

A trim round asks one question of the branch's changes: should this exist at all?

1. When the tree is not clean, commit the work with `/commit`, so each round's commit holds only
   its own cuts.
2. Run at least three rounds, also when a round removes nothing. After the third, go on while the
   last round made a cut, up to five rounds. Round `<k>`:
   1. Spawn a new `simplicity-reviewer`, never one from an earlier round, so it is not anchored on
      that round. Give it the range `origin/develop...HEAD` and the task's issue,
      `gh issue view <n> -R BorjaElizalde/template-agentic --comments`, with `<n>` from the branch name
      `<type>/<n>-<slug>`.
   2. Apply the cuts that hold, under the Judgment Guidelines. A cut removes a thing: a parameter,
      a branch, an option, a helper, a layer, a file, and the tests of what it removed. Behaviour
      the issue asks for stays, and the same logic in fewer lines is not a cut. Say in one line
      why each rejected cut stays.
   3. Stage every change with `git add -A`, in a call of its own, and read the round's count from
      `git diff --cached --shortstat`. Watch the `+`: a round that adds many lines is rewriting,
      not trimming, so take the rewrite back. Commit a round that changed the tree with the
      subject `Trim round <k>: +<added> -<removed>`, then state that count, `+0 -0` for a round
      with no change.
3. Run no `/gate` between rounds: it runs once, after the last.
4. End with every round's count in one line, for example `Trim: +4 -41, +0 -9, +0 -0`.
