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
| `deploy_workflow` | The GitHub Actions workflow the merge into `main` starts, which `/release` waits for; empty for none |
| `agent_merges` | Whether the agent may squash-merge its own PR into `develop` once every check on its head, `gate` among them, has passed (default `false`: the owner merges). With it, `settings.json` allows `gh pr merge` and `bash-guard.sh` decides every merge; for a repository whose plan has no rulesets, the guard is then the only place `gate` is enforced |

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
files. Given no issue, `/task:finish` finishes every task whose issue is closed, and
`/task:start` does the same first: a PR merged on GitHub closes its issue, and the next start
finishes its task.

Both are skills of one plugin, `.claude/skills/task/`, so they share its `scripts/task.sh`
through `${CLAUDE_PLUGIN_ROOT}` and no repository needs a Makefile for them. Claude Code loads a
plugin under `.claude/skills/` in place, with no install and no settings entry, from the folder a
session starts in: the main checkout, or a task's worktree. Claude itself is started however the
machine prefers, for example `alias claude-rc='caffeinate -i claude --remote-control'`.

## What the project owns

`.claude/memory/MEMORY.md` and `renovate.json` are seeded once (`_skip_if_exists`): an update
never touches them, and a first copy into an existing repository keeps the repository's own file.
The seeded `renovate.json` keeps Renovate's github-actions manager off the template's CI files, so
their action pins arrive only in the template's update PR; a repository that keeps its own file
adds the same `ignorePaths`. The project's `CLAUDE.md`
is its own: the template never writes it, and its Product Stage is what the Judgment Guidelines in
`.claude/rules/agentic.md` decide against. That rule file has no `paths:`, so Claude Code loads it
in every session.

The project's own hooks live in `.claude/hooks/project/<event>/`, a folder the template never
writes into. `settings.json` runs `.claude/hooks/project.sh <event>` on `SessionStart`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse` and `Stop`, with no matcher, and that runs every
file in the event's folder in name order, each with the hook payload on stdin. Each file is an
executable program; one that cares about the tool reads `.tool_name` from the payload. The
contract is the one Claude Code gives a command hook:

- stdout passes through; on `SessionStart` and `UserPromptSubmit` it becomes context;
- the first script that exits 2 stops the run, its stderr is the reason, and the hook exits 2;
- a script that fails any other way is reported on one stderr line that names it, the rest still
  run, and the hook exits 1;
- JSON output is not supported: several scripts' JSON can't be merged into one answer.

All scripts of an event share that hook's timeout. Task sessions run them too: the `--settings`
a session starts with adds its hooks to the project's `settings.json` and replaces none of them.

Every other file belongs to this template: change it here, not in a project.

## One settings file for every stack

Claude Code reads one committed project settings file, so `.claude/settings.json` belongs here
and carries every stack's permissions and environment side by side. The stacks never set the same
key to different values, so a line one stack needs is inert in the others: a TypeScript project
never calls `pip`, and an empty `VIRTUAL_ENV` changes nothing there. A new stack adds its lines
here.

## CI

`.github/workflows/gate.yaml` runs on every PR into `develop`, `staging` or `main`. It first
checks where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or a
`bugfix/*` PR of one commit, from the repository's own branches. Then it runs the stack layer's
checks. Rulesets require its `gate` check on all three branches, and `/release` waits for it on
each promotion PR.

## Plug-in points for a stack layer

A stack layer supplies these fixed names. When one is missing, nothing runs in its place, except
the CI checks: the `Gate` workflow fails without them, so a project never gets a CI that checks
nothing.

| File | Contract |
|---|---|
| `.github/actions/stack-gate/action.yaml` | The composite action the `Gate` workflow runs on every PR into `develop`, `staging` or `main`, after its PR-source check and the checkout. It calls the stack's tools directly, never `make gate`, so a change that relaxes the local gate can't relax CI. |
| `.claude/hooks/practices/registry.jq` | `kind($path)` returns the file's kind or `null`; `practices($ctx; $kind)` streams `{level, text}`, with level `stop` or `remind`, from the stack's practice modules beside it. `lib.jq` provides `edit_context`, the text helpers, and the reason form a skipped check gives (`reason_form`, `reason_steps`). |
| `.claude/hooks/stack/format.sh` | Runs after every Edit/Write with the hook payload on stdin. |
| `.claude/review-wave.md` | Names the plan reviewer, the review wave, the last pass, and the resolver for lint, format and type failures that `/agentic-flow` runs. |
| `make gate` | The project's full local validation, which `/gate` runs. The stack layer provides it. |

## Develop

This repository works on the same three branches as every project. Feature PRs squash into
`develop`; `/release` merges `develop` into `staging` and `staging` into `main`, where `Build`
tags the next version; a `bugfix/` branch of one commit merges into `staging`. Rulesets hold
each branch to PRs with a passing `gate`, `staging` and `main` to merge commits and `develop` to
squashes. Commits use the GitHub noreply address set in the clone's git config.

The repository is a project of its own template: `.claude/` holds the whole harness, rendered
from the working tree with the answers `.claude/agentic.conf` records (its own issues as the
issues repository, `Build` as its deploy workflow), so work here runs the guards and skills every
project gets. Being the source, it has no answers file for Copier or Renovate to update. Instead
`make render` makes `.claude/` match a render of the working tree, leaving the paths this
repository owns (the memory stores, the local settings and the project's hooks folder). A pre-commit hook runs it on every
commit that changes `template/` and stops the commit when it re-rendered something, so the
re-render is staged with the change. Once per clone, run `uvx pre-commit install` and
`bash .claude/skills/task/scripts/task.sh point-memory`.

`make gate` renders the template and runs the rendered guard, protocol, memory checker and
`task.sh` suites. It also runs `make render` on a copy of the working tree and fails when that
changes `.claude/`, for a commit made without the hook. The
`Gate` workflow runs the same target on every PR into `develop`, `staging` or `main`, after it
checks where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or a
`bugfix/*` PR of one commit, from this repository's own branches. `Build` runs the gate again on
`main` before it tags.
