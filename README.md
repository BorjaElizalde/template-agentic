# template-agentic

A [Copier](https://copier.readthedocs.io/) template for the language-neutral half of an agentic
coding setup: the Claude Code guards, skills and agents, and the issue → worktree → session
workflow. A project applies it side by side with one stack layer (for example
`template-python-service`), each layer with its own answers file.

## Apply and update

```bash
uvx copier copy <template-url> .            # writes .copier-answers.agentic.yaml
bash .claude/skills/task/scripts/task.sh point-memory    # once per clone: Claude's auto memory → .claude/memory/
uvx copier update -a .copier-answers.agentic.yaml
```

Every merge to `main` is a release: the `Build` workflow re-runs `make gate` on the merged result,
then tags the next `YYYYMMDD.N` version (a PEP 440 version, which Copier and Renovate order by).
Projects take it as an update PR (Renovate's Copier manager, or `copier update` by hand). The
template uses no unsafe Copier feature (Jinja extensions, migrations, tasks, or `_external_data`
outside the project root), so an update runs without `--trust`.

## Questions

| Question | Used for |
|---|---|
| `issues_repo` | Where task issues live (`owner/name`): issue lookup, PR `Closes` lines, session prompt |
| `worktree_root` | Folder for linked worktrees, relative to the main checkout |

Repositories that share an issue tracker and a worktree folder give the same answers. Scripts read
them from `.claude/agentic.conf`, the only rendered file they source, so they stay plain shell
that the template's tests run directly.

Every project works on the same three branches: feature PRs go into `develop`, and `/release`
promotes `develop` to `staging` to `main` with merge commits. All three are protected, and
`develop` is the default branch: GitHub links a PR's `Closes` line to its issue only on a PR into
the default branch.

## Tasks

Every task, and every subagent session, is an issue with its own worktree and session; the
worktree is the agent's workspace even for a research task. `/task:start` finds or creates the
issue, creates `<worktree_root>/<n>-<slug>/<repo>` (`<repo>` is the main checkout's folder name,
so a task that spans repositories gets one issue folder holding each repository's worktree), and
opens the session. On an issue that already has work it picks that work up: its worktree, else its
branch (left without a worktree, or pushed from another clone), and its session, brought to the
front while it runs and resumed when it doesn't. `/task:finish` closes the issue once its result
is delivered, then the session, the worktree and the branch; it refuses while the branch has
commits on no remote branch and in no merged PR, or the worktree has uncommitted or untracked
files.

Both are skills of one plugin, `.claude/skills/task/`, so they share its `scripts/task.sh`
through `${CLAUDE_PLUGIN_ROOT}` and no repository needs a Makefile for them. Claude Code loads a
plugin under `.claude/skills/` in place, with no install and no settings entry, from the folder a
session starts in: the main checkout, or a task's worktree. Claude itself is started however the
machine prefers, for example `alias claude-rc='caffeinate -i claude --remote-control'`.

## What the project owns

`.claude/memory/MEMORY.md` and `.claude/release.md` are seeded once (`_skip_if_exists`): an
update never touches them, and a first copy into an existing repository keeps the repository's
own file. The project's `CLAUDE.md` is its own: the template never writes it, and its Product
Stage is what the Judgment Guidelines in `.claude/rules/agentic.md` decide against. That rule
file has no `paths:`, so Claude Code loads it in every session. Every other file belongs to this
template: change it here, not in a project.

## One settings file for every stack

Claude Code reads one committed project settings file, so `.claude/settings.json` belongs here
and carries every stack's permissions and environment side by side. The stacks never set the same
key to different values, so a line one stack needs is inert in the others: a TypeScript project
never calls `pip`, and an empty `VIRTUAL_ENV` changes nothing there. A new stack adds its lines
here.

## Plug-in points for a stack layer

A stack layer supplies these fixed names. When one is missing, nothing runs in its place.

| File | Contract |
|---|---|
| `.claude/hooks/practices/registry.jq` | `kind($path)` returns the file's kind or `null`; `practices($ctx; $kind)` streams `{level, text}`, with level `stop` or `remind`, from the stack's practice modules beside it. `lib.jq` provides `edit_context`, the text helpers, and the reason form a skipped check gives (`reason_form`, `reason_steps`). |
| `.claude/hooks/stack/format.sh` | Runs after every Edit/Write with the hook payload on stdin. |
| `.claude/review-wave.md` | Names the plan reviewer, the review wave, the last pass, and the resolver for lint, format and type failures that `/agentic-flow` runs. |
| `make gate` | The project's full validation, which `/gate` runs. The stack layer provides it in the Makefile it owns. |

## Develop

This repository works on the same three branches as every project. Feature PRs squash into
`develop`; `/release` merges `develop` into `staging` and `staging` into `main`, where `Build`
tags the next version; a `bugfix/` branch of one commit merges into `staging`. Rulesets hold
each branch to PRs with a passing `gate`, `staging` and `main` to merge commits and `develop` to
squashes. Its own
`.claude/skills/` carries `/commit`, `/gate`, `/pull-request` and `/release` as rendered copies
of the skills this template ships, with its own issues as the issues repository, and
`.claude/release.md` holds its release facts. Commits use the GitHub noreply address set in the
clone's git config.

`make gate` renders the template and runs the rendered guard, protocol, memory checker and
`task.sh` suites, and checks that the repository's own shared skills match a fresh render. The
`Gate` workflow runs the same target on every PR into `develop`, `staging` or `main`, after it
checks where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or a
`bugfix/*` PR of one commit, from this repository's own branches. `Build` runs the gate again on
`main` before it tags.
