# template-agentic

A [Copier](https://copier.readthedocs.io/) template for the language-neutral half of an agentic
coding setup: the Claude Code hooks, rules, skills and agents, the issue → worktree → session
task workflow, and the `Gate` and `Branch protection` workflows. A stack template, such as
`template-python-service`, carries it inside each of its releases and fills its plug-in points for
one stack, so a project applies the stack template only.

## Bundle into a stack template

A stack template releases with `release.sh`, which bundles this template into its `main` and tags
the result as a commit that no branch holds. `bundle.sh` does the bundle: it copies this template's
`template/` into the stack template's `template/`, and its `copier.yaml` to `agentic/copier.yaml`,
and refuses a stack template that has its own copy of a file it bundles. The release commit's
second parent is the release before it, so the compare in a project's update PR shows only what
changed. A stack template takes this template in four steps:

1. Apply this template to the stack template's own repository:

   ```bash
   uvx copier copy https://github.com/BorjaElizalde/template-agentic.git .
   ```

   The copy writes `.copier-answers.agentic.yaml`, which records the version to bundle and which
   Renovate's Copier manager moves in an update PR. It also brings the `Branch protection` workflow
   and the `Gate` workflow, so put the stack template's own CI checks in
   `.github/workflows/gate-checks.yaml` at its root, with the contract below, except that they may
   run `make gate`. Make its `renovate.json` extend `renovate/base`, with only
   `.github/workflows/gate.yaml` in `github-actions.ignorePaths`, so that Renovate updates the
   pins of its own checks and leaves this template's to its update PR.
2. Release from the `Build` workflow on each merge to `main`: in the checkout of
   `main`, with a git identity and `contents: write`, clone this repository at the recorded
   version and run `bash <clone>/release.sh <tag>`, which pushes the tag. `GITHUB_TOKEN` may push
   it: GitHub refuses a workflow file at the root `.github/workflows/` only.
3. Open the stack template's `copier.yaml` with `!include agentic/copier.yaml` and `---`, then
   give its own settings and questions. Copier joins the two documents' `_skip_if_exists` lists,
   and where both name `_answers_file` or a question, the stack template's wins. So list only its
   own seeded files, name its own `_answers_file`, and give its questions names that this
   template does not use. They come after this template's questions, so they and its files may
   read this template's answers. Add no answers-file template: the bundle brings
   `{{ _copier_conf.answers_file }}.jinja`.
4. Start the validator of a question that has no default with
   `{% if 'issues_repo' not in _copier_answers %}`, whose message says to copy a release tag. It
   stops a copy of a branch.

## What a stack template supplies

A stack template supplies these files in its `template/`, so that each project gets them:

| File | Contract |
|---|---|
| `.github/workflows/gate-checks.yaml` | The workflow that the `Gate` workflow calls on every PR into `develop` or `staging`, through `workflow_call` with one required boolean input, `skip`. `skip` is true on a draft, on the promotion of `develop`, and on a PR whose every changed path the skip lists match, and every job skips then, with `if: ${{ !inputs.skip }}`. It checks out the code and calls the stack's tools directly, never `make gate`. Its checks report as `gate / <job>`. |
| `.github/gate-checks/gateignore` | Optional: the stack's skip list, the paths that its checks never read, as `.gitignore` patterns. Each pattern takes its reason on the `#` lines directly above it, and a folder is written `dir/**`. The `Gate` workflow reads it, then the project's `.github/gateignore`, which this template seeds once: a later pattern wins, so a project's `!` pattern runs the checks on a path the stack lists. As in `.gitignore`, a `!` can't put back a file inside a folder that a pattern matches, until `!dir/**/` puts back the folders. Without a list, every check runs on every PR. |
| `.claude/hooks/practices/registry.jq` | `kind($path)` returns the file's kind or `null`; `practices($ctx; $kind)` streams `{level, text}`, with level `stop` or `remind`, from the stack's practice modules beside it. `lib.jq` provides `edit_context`, the text helpers, and the reason form a skipped check gives (`reason_form`, `reason_steps`). |
| `.claude/hooks/stack/format.sh` | Runs after every Edit or Write, with the hook payload on stdin. |

The stack template seeds the project's `Makefile`, which includes only the stack's make fragment.
That fragment defines `gate`, the project's full local validation, which `/gate` runs, and must
include this template's:

```make
include .claude/agentic.mk
```

`.claude/agentic.mk` gives `make claude` and `make help`. The stack fragment must describe each
target on its rule line, as `gate: ## <description>`, for `make help` to list it. It extends a
target of `agentic.mk` only with a prerequisite or a variable set after the include, never with a
second recipe.

The stack's rules go in its `template/.claude/rules/`, beside the bundled `agentic.md`,
`conventions.md` and `writing.md`. One of them lists the stack's skipped-check directives and
the tools whose docs to read, which `conventions.md` leaves to the stack.

Claude Code reads one shared project settings file, `.claude/settings.json`, and this template
renders it for every stack. A new stack adds its permissions and environment to
`template/.claude/settings.json.jinja` here, each line one that changes nothing in the other
stacks, as the `pip` deny changes nothing outside Python.
