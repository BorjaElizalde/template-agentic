---
name: trim
description: Use once an execution task's work is done and `/gate` is green, before its PR. Checks for a simpler design first, then cuts in counted passes what the task did not need.
---

Step back from what you built and simplify it, as a developer does before asking for review: the
passes are yours on purpose, and need no fresh agent.

1. When the tree is not clean, commit the work with `/commit`, so each pass's commit holds only its
   own cuts.
2. **Design check.** Spawn one `simplicity-reviewer`. Give it the task's issue,
   `gh issue view <n> -R BorjaElizalde/template-agentic --json title,body,comments`, with `<n>` from the branch
   name `<type>/<n>-<slug>`. It runs before the passes: there is no point in trimming what a
   simpler design removes.
3. Decide on its flag under the Judgment Guidelines: take the simpler design unless a reason
   stands against it, and name that reason. To take it, rebuild, run `/gate` and commit.
4. **Passes.** Run at least three, also when one removes nothing: `existence`, `structure`, then
   `surface`. After the third, go on with every lens while the last pass made a cut, up to five
   passes. Pass `<k>`:
   1. Read the branch's changes, `git diff origin/develop...HEAD`, and make the cuts the sections
      below find. A cut is done only when it reaches the callers, the tests, the fixtures and the
      docs of what it removed.
   2. Stage the files the pass changed, by name, and read its count from
      `git diff --cached --shortstat`. Watch the `+`: a pass that adds many lines is rewriting,
      not trimming, so take the rewrite back. Commit a pass that changed the tree with the subject
      `Trim pass <k>: +<added> -<removed>`, and state that count. A pass with no change states
      `+0 -0` and, in one line, what it checked.
5. Run no `/gate` between passes.
6. End with two lines:

   ```
   Design: <the flag in a few words, or "no simpler design"> - <taken, or kept: why>
   Trim: +4 -41, +0 -9, +0 -0
   ```

## Questions

Hold everything the branch adds, from a file to a sentence, against these questions in order, and
stop at the first one that gives a cut:

1. Does it need to exist: did the issue ask for it?
2. Does this codebase already have it?
3. Does the standard library, the platform or an installed dependency do it?
4. Can it be one line a reader gets at a glance?
5. Otherwise, is it the least code that works?

## Cuts

A pass looks first through its lens, and a cut outside it still counts.

- **Existence**: what should not exist.
  - *delete*: dead code, unused parameters and options, features the issue did not ask for,
    "for later" generality, dead compatibility paths, edits unrelated to the task.
- **Structure**: what should not be its own thing.
  - *one use*: an abstraction with one implementation, a wrapper with one caller, an adapter with
    no second implementation, a layer that only passes through, config nobody sets.
  - *reuse*: this codebase, the standard library, the platform or an installed dependency already
    does it.
  - *merge*: near-copies that must change together, or one decision made in several places.
  - *state*: hidden or mutable state that could be derived, local, or returned.
- **Surface**: what a reader stumbles on. Run the reader test on the result.
  - *guards*: a check, `try` block or validator for a state that cannot happen on a trusted path.
  - *comments*: a comment that narrates or restates the code. The why the code cannot show stays.
  - *instructions*: in a skill, a rule or a prompt, a sentence that repeats another, or that
    changes nothing its reader does.

**Reader test.** A reader pays for layers to trace and state to hold. Can a new reader say where
a value comes from, and what can change it, in about half a minute? A cut that removes a layer or
a piece of state counts even when the line count barely moves.

**Never cut** what the issue asks for, validation at a trust boundary, error handling that
prevents data loss, security, or accessibility. Code that is moved or merged keeps its error
handling and validation.

**Not a cut:** the same logic in fewer lines, a one-liner that needs decoding, or a helper that
exists only to make a function shorter. Split by job, never by length.

## Proof

No case, no cut, and no "nothing to cut" without having looked. Before "unused", grep the callers
and give the count. Before "cannot happen", show the call path. Before "it already exists", name
the path or the function. Before "a spec needs it", read the spec.
