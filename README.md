# template-agentic

A [Copier](https://copier.readthedocs.io/) template for the language-neutral half of an agentic
coding setup: the Claude Code guards, skills and agents, and the issue → worktree → session
workflow. A project applies it side by side with one stack layer (for example
`template-python-service`), each layer with its own answers file.

## Apply and update

```bash
uvx copier copy <template-url> .            # writes .copier-answers.agentic.yml
make point_memory                           # once per clone: Claude's auto memory → .claude/memory/
uvx copier update -a .copier-answers.agentic.yml
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
promotes `develop` to `staging` to `main` with merge commits. All three are protected.

`make worktree issue=<n>` creates `<worktree_root>/<n>-<slug>/<repo>`, where `<repo>` is the main
checkout's folder name. A task that spans repositories gets one issue folder holding each
repository's worktree.

## What the project owns

`CLAUDE.md`, `Makefile`, `.claude/memory/MEMORY.md` and `.claude/release.md` are seeded once
(`_skip_if_exists`): an update never touches them, and a first copy into an existing repository
keeps the repository's own file. `CLAUDE.md` imports `@.claude/agentic.md`; the `Makefile`
includes `harness.mk` and the stack's `stack.mk`. Every other file belongs to this template:
change it here, not in a project.

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
| `.claude/hooks/practices/registry.jq` | `kind($path)` returns the file's kind or `null`; `practices($ctx; $kind)` streams `{level, text}` from the stack's practice modules beside it. `lib.jq` provides `edit_context` and the text helpers. |
| `.claude/hooks/stack/format.sh` | Runs after every Edit/Write with the hook payload on stdin. |
| `.claude/review-wave.md` | Names the plan reviewer, the review wave, the last pass, and the resolver for lint, format and type failures that `/agentic-flow` runs. |
| `stack.mk` | Provides `make gate`, which `/gate` runs. |

## Develop

`make gate` renders the template and runs the rendered guard, protocol, memory checker and
`issue.sh` suites. The `Gate` workflow runs the same target on every PR, and `Build` runs it again
on `main` before it tags.
