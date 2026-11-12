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
shared Renovate rules, `renovate/base.json` (see [What the project owns](#what-the-project-owns)),
open that PR at any time and outside every group, so a release reaches projects within hours,
each template layer in its own PR. The template uses no unsafe Copier feature (Jinja extensions,
migrations, tasks, or `_external_data` outside the project root), so an update runs without
`--trust`.

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
the default branch. Beside the rulesets, turn on *Automatically delete head branches* in the
repository's settings: GitHub then deletes a merged PR's branch on origin. No script deletes a
remote branch, so without it the branches of finished tasks pile up there.

## Tasks

Every task, and every subagent session, is an issue with its own worktree and session; the
worktree is the agent's workspace even for a research task. `/task:start` finds or creates the
issue, creates `<worktree_root>/<n>-<slug>/<repo>` (`<repo>` is the main checkout's folder name,
so a task that spans repositories gets one issue folder holding each repository's worktree), and
opens the session. On an issue that already has work it picks that work up: its worktree, else its
branch (left without a worktree, or pushed from another clone), and its session, brought to the
front while it runs and resumed when it doesn't. `/task:finish` closes the issue once its result
is delivered, then the session, the worktree and every local branch of the issue (`*/<n>-*`: a
task can open a second branch for a follow-up PR); it refuses before it removes anything while one
of those branches has commits on no remote branch and in no merged PR, or the worktree has
uncommitted or untracked files.

A task starts in one of two modes, and its branch type is its mode from its start to its finish:

| Mode | How its session works | Branch types | Result |
|---|---|---|---|
| Execution, the default | Alone: it never waits for a person | `feat`, `fix`, `refactor`, `chore`, `research` | A PR. For `research`, an answer: a PR for a document, or a result comment |
| Design | With the owner, who answers in its Terminal tab: it asks what is the owner's to decide, and may end its turn on a question | `design` | An answer, delivered as a research task's is: the decisions taken, and the issues for the work |

The main session starts a design task only when the owner asks to work it out together ("with
me", "let's design", "let's discuss"), never on its own guess. `task.sh start` reads the mode from
the task's branch at every start, so a resumed session keeps it; nothing else stores it, neither a
start argument, a label nor a file. The type names a new branch only, so a task keeps its mode for
life: to talk an execution task through, the owner uses its PR, and to build what a design task
decided, the main session starts execution tasks from its issues. `task.sh start` refuses a type
it does not know, since a mistyped one would fix the wrong mode for the task's life. The mode is
said in three places: the branch name, the session line of `task.sh start`, for a new, a resumed
and a running session, and the status line of a design task, which says `design mode`.

Every open issue is in one of four states, each read from a fact GitHub already holds:

| State | How it is marked | Who clears it |
|---|---|---|
| Ready | Open, no `backlog` label, no open "blocked by" issue, no task worktree | nobody |
| In progress | Has a task worktree | nobody |
| Blocked | A "blocked by" link to an open issue | itself, when the blocker closes |
| Parked | The `backlog` label, and a comment that starts with `Parked:` and gives the reason | the owner, by word |

`task.sh start` refuses a blocked or a parked issue before it does anything else, and names the
open blockers or the reason in the last `Parked:` comment, so no agent starts one. The owner never
labels or links an issue by hand: the main session does it, as the start skill says. It links an
issue with `gh issue edit --add-blocked-by`, and parks one only on the owner's word with
`task.sh park <n> <reason>`, which posts the `Parked:` comment, then adds the label. The park
creates the label on its first use in a repository, with `gh label create --force`, so no project
needs a step to have it. Releasing removes the label. One label serves every reason: there is no
label per reason, no project board, no issue type (GitHub offers them only to organizations) and
no parent issue.

To plan a backlog, the owner says "plan X", and the main session starts an ordinary `research`
task, or says "plan X with me", and the main session starts a `design` task. Either session studies
the code and the open issues, then creates one issue per piece of work, each with its goal, its
scope and what done means. "Blocked by" links put them in order, and each one is parked with a
reason that names the planning issue. The result is a comment on the planning issue that lists
them, which `/task:finish` accepts for a research or a design task. A research session never
waits for the owner, who corrects the plan afterwards; a design session works it out with the
owner as it goes. Either way, the owner tells the main session which issues to release.

The main session follows its tasks through two commands of `task.sh`, and each does one thing:

- `cleanup` finishes every task whose issue is closed, and prints one line per task it finished
  or refused to finish, with the reason. A PR merged on GitHub closes its issue, but nothing else
  finishes its task. `/task:finish` with no issue runs it.
- `status` only reads, and shows the whole backlog: every open issue once, under the headings In
  progress, Ready, Blocked and Parked, with no heading where no issue is. Under In progress is one
  line per task worktree of this checkout: the issue and its short title, `design mode` for a
  design task, its session (`busy`, `idle`, `waiting`, or none), its newest PR with its state and
  check result, and how long ago the session last wrote its transcript. The other issues come
  from one `gh issue list`, one line
  each with the whole title, lowest number first: a blocked line names the open issues it waits
  on, and a parked line its reason. An issue goes under the first state that fits: in progress,
  then parked, then blocked, then ready. So an issue a planning task left parked and blocked shows
  under Parked, and its line names its open blocker too. An issue whose only task worktree is in
  another repository of the project is not in progress here: it shows under the backlog heading
  that fits. `status` calls `claude agents` only where there is a task worktree.

A line ends in `needs attention` when the task's session waits for an answer, or has been idle or
gone for 10 minutes (`QUIET_MINUTES`) since it last wrote its transcript. A busy session is
working, and one that went quiet only just now often waits for a background check that wakes it
when the check finishes. Idle notices (`SendMessage` with `notify_when_idle`) are not used: they
can't be delayed, so they would fire on exactly those pauses.

Both run by themselves, cleanup first, at two moments, where the status gives only its task lines,
with no heading and no backlog:

- each `/task:start`, whose lines leave out the task it starts;
- a session that starts or resumes in a main checkout, through a `SessionStart` hook in
  `settings.json` (`startup|resume`) that runs `task.sh on-session-start` and puts the lines in
  the session's context, so a restart forgets nothing.

A main session that runs a `/loop` runs `status` on each round, which prints every task and the
backlog even when no task needs attention. The hook makes a session start slower, since its
cleanup can close sessions and remove worktrees. Claude Code runs it in the background, and the
session's first answer waits for it. A hook can't call a skill or start a turn: it only adds its
output to the session's context, which the owner doesn't see. So its output ends with one line
that sends the session to `/task:status` for its first reply. Claude Code passes on 10,000
characters of a hook's output, and only a preview of the first 2,000 when there are more, so the
lines stay short: about 40 tasks fit. The backlog has no such bound, so the hook leaves it to
`/task:status`. It prints nothing in a task worktree, so task sessions start untouched, nor where
there is no task worktree, where it calls neither `gh` nor `claude`. A cleanup refusal is
reported and the session starts anyway. When `gh` or `claude agents` can't answer, it says the
tasks are unknown, and to report them through `/task:status` once they answer, and exits 0.

The owner reads the status through `/task:status`. The script gives the facts and the main session
writes the reply, since a script can't put a goal in plain words or say what the owner should do.
The skill runs the cleanup and the status, reads each task's issue for its goal and any
`Owner steps` comment, and reads the last message of each idle or waiting session. It acts on each
line marked `needs attention` where the main session can, for example it sends a session back to
fix failed checks. Then it answers with one card per task: the goal, where the task stands, and
what the owner should do, with the main session's pick. The cards that need the owner come first.
Three short lists follow the cards: Ready, Blocked and Parked, one line per issue. A list with no
issue is left out, and a list of more than ten shows its first ten and how many more there are.
A task whose issue is closed shows only in the closing "Cleaned up" list. The main session
reports the status this way when the owner asks for it, in its first reply after a session start,
and at the end of each `/task:start`; a `/loop` round does it when a line needs attention. The
format is only in the skill, which loads when it is used, so a task session never carries it. The
name keeps the plugin's prefix: a bare `/status` skill would replace Claude Code's built-in
command.

A task session is an interactive `claude` process in a Terminal tab (`open_session` in
`task.sh`), never `claude -p`, the Agent SDK or an API key. `settings.json` also denies
`claude -p` and `claude --print` to every session, since a print run is billed at API prices.
These deny lines match only a command that starts that way, so a form like `claude --model x -p`
still gets through.

Each text a session launches with lives in one file of `session/`. A `PermissionRequest` hook in
`settings.json` denies every permission prompt, in both modes: nobody answers those. The system
prompt is `prompt.md`, the words both modes share, then the mode's own words, `execution.md` or
`design.md`. `claude` takes one appended system prompt, so the tab's shell joins the two files
when it launches the session. Nobody answers an execution session, so it never waits for a person:
`--disallowed-tools AskUserQuestion` removes the question tool, `execution.md` tells it to take
the option it would recommend and go on, and a `Stop` prompt hook in `settings.json` sends it back
to work when it ends its turn on a question. The hook's model call runs on the session's own
login, so it needs no API key either. A design session keeps the question tool and goes without
the `Stop` hook: `claude --settings` takes one file or JSON string, so `task.sh` gives it the
settings less the hook as JSON. It asks the owner what is the owner's to decide, and may end its
turn on a question. `/task:status` gives such a question the ✋ mark: the owner answers it in the
session's Terminal tab, and the main session never answers it for the owner, nor sends the
session back to work past it. `task.sh` finds a running session in
`claude agents --json`, the supported way to read session state from outside Claude Code, as the
interactive session whose working directory is the worktree; it finds the session's Terminal tab
by that process's tty.

`/task:start`, `/task:finish` and `/task:status` are skills of one plugin, `.claude/skills/task/`,
so they share its `scripts/task.sh` through `${CLAUDE_PLUGIN_ROOT}` and no repository needs a
Makefile for them. Claude Code loads a plugin under `.claude/skills/` in place, with no install
and no settings entry, from the folder a session starts in: the main checkout, or a task's
worktree. Claude itself is started however the machine prefers, for example
`alias claude-rc='caffeinate -i claude --remote-control'`.

## Trim before the PR

A stack's lint checks and Claude Code's `/simplify` clean the form of AI-written code, and
`/simplify` skips every fix that would change behaviour, so none of them removes a thing that
should not exist. `/trim` does. It first spawns a `simplicity-reviewer`, a read-only agent that
works out the smallest design for the task's issue before it reads the branch, and flags a simpler
design than the one built. Then the session cuts what the task did not need in passes of its own,
and commits each with its count of lines added and removed. `execution.md` runs `/trim` in every
execution task that ends in a PR, because a skill or agent that no step calls does not run.
`/agentic-flow` runs it before `/simplify`. `/pull-request` checks nothing of it.

The text of both draws on [Ponytail](https://github.com/DietrichGebert/ponytail),
[pstack](https://github.com/backnotprop/pstack) and Cursor's
[deslop](https://github.com/cursor/plugins/tree/main/cursor-team-kit/skills/deslop).

## What the project owns

`.claude/memory/MEMORY.md` and `renovate.json` are seeded once (`_skip_if_exists`): an update
never touches them, and a first copy into an existing repository keeps the repository's own file.
The project's `CLAUDE.md` is its own: the template never writes it, and its Product Stage is what
the Judgment Guidelines in `.claude/rules/agentic.md` decide against. That rule file has no
`paths:`, so Claude Code loads it in every session. Every other file belongs to this template:
change it here, not in a project.

The seeded `renovate.json` takes every rule from a shared preset in `renovate/` at this
repository's root, outside `template/` so it is never rendered. The preset is two files:

- `renovate/base.json` holds the rules. This repository's own `renovate.json` extends it, because
  its CI files are its own and Renovate keeps their action pins current.
- `renovate/default.json` extends `base` and adds the template's CI files to the github-actions
  manager's `ignorePaths`, so their action pins arrive only in the template's update PR. A project
  extends `default`.

Renovate reads both files from this repository's default branch, `develop`, with no tag pin: a
change merged there reaches every project on its next Renovate run. The rules run Renovate on the
1st of each month. They put every minor and patch update in one PR and each major update in its
own, bump the version ranges, refresh the lock files, and move the Python image and the Python
version together. Template updates (the `copier` manager) are the exception: they come at any time
and outside every group, so a release reaches a project within hours, each template layer in its
own PR.

The project's `renovate.json` is this pointer, which no release needs to change:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "description": "Seeded once by the agentic template. Every rule comes from the shared preset; add the project's own as packageRules here, and no github-actions ignorePaths, which would replace the preset's list.",
  "extends": ["github>BorjaElizalde/template-agentic//renovate/default"]
}
```

A project made before release `20261110.1` has its rules in its own file. It replaces its
`renovate.json` with the file above, once: `20261110.1` is the first release whose seed is the
pointer, and the file is seeded once, so no update can deliver it. A repository that kept its own
`renovate.json` at the first copy does the same, and moves its own rules into `packageRules`.

A project adds its own rules as `packageRules` in its `renovate.json`: Renovate appends them after
the preset's, so they win where both set an option. The project's file must not hold its own
`github-actions.ignorePaths`. Renovate does not join two `ignorePaths` lists: the project's list
replaces the shared one, and a template CI file left off it gets Renovate's PRs.

## One settings file for every stack

Claude Code reads one committed project settings file, so `.claude/settings.json` belongs here
and carries every stack's permissions and environment side by side. The stacks never set the same
key to different values, so a line one stack needs is inert in the others: a TypeScript project
never calls `pip`, and an empty `VIRTUAL_ENV` changes nothing there. A new stack adds its lines
here.

`settings.json` allows `gh issue create`, `list`, `view`, `comment` and `edit`; the start skill and
the session prompt ask for issue comments. It grants no other `gh issue` call and no `gh label`,
which leaves each of them to the auto-mode classifier:

- `gh issue close` is allowed only inside `/task:finish`, by its `allowed-tools`, because the next
  cleanup finishes a task whose issue is closed;
- `gh issue delete` and `gh issue transfer` can't be undone;
- `gh label` runs only inside `task.sh park`, which a session calls through `bash`, as it calls
  every `task.sh` command.

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
repository owns (the memory stores and the local settings). A pre-commit hook runs it on every
commit that changes `template/` and stops the commit when it re-rendered something, so the
re-render is staged with the change. Once per clone, run `uvx pre-commit install` and
`bash .claude/skills/task/scripts/task.sh point-memory`.

`make gate` renders the template, runs shellcheck on every script in the render and in `tests/`,
and runs the rendered suites, which cover every hook and script. It also runs `make render` on a
copy of the working tree and fails when that changes `.claude/`, for a commit made without the
hook. The `Gate` workflow runs the same target on every PR into `develop`, `staging` or `main`,
after it checks where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or
a `bugfix/*` PR of one commit, from this repository's own branches. `Build` runs the gate again on
`main` before it tags.
