# template-agentic

A [Copier](https://copier.readthedocs.io/) template for the language-neutral half of an agentic
coding setup: the Claude Code hooks, rules, skills and agents, the issue → worktree → session
task workflow, and the `Gate` workflow. A stack template, such as `template-python-service`,
carries it inside each of its releases and fills its plug-in points for one stack, so a project
applies the stack template only, with one answers file and one update PR.

## Bundle into a stack template

A stack template's release carries a copy of this one, which `bundle.sh` writes: it copies this
template's `template/` into the stack template's `template/`, and its `copier.yaml` to
`agentic/copier.yaml`. It refuses a stack template that has its own copy of a file it bundles.
`template-python-service` takes it this way:

- It applies this template to its own repository. Its `.copier-answers.agentic.yaml` then
  records the version that a release bundles, and Renovate's Copier manager moves that version in
  an update PR.

  ```bash
  uvx copier copy https://github.com/BorjaElizalde/template-agentic.git .
  ```

- On each merge to `main`, its `Build` workflow runs the `release-tag` target of its `Makefile`
  after the gate. The target clones this repository at the recorded version, runs
  `bash <clone>/bundle.sh .` on `main`'s tree, and tags the result as a commit that no branch
  holds. Its gate runs the same target in a temporary clone before it renders a project.
- Its `copier.yaml` opens with `!include agentic/copier.yaml` and `---`, then gives its own
  settings and questions. Copier joins the two documents' `_exclude`, `_jinja_extensions`,
  `_secret_questions` and `_skip_if_exists` lists; for any other setting or question both name,
  the stack template's wins. So it names its own `_answers_file`, and gives its questions names
  that this template does not use. Its questions come after this template's, so they and its
  files may read this template's answers. It has no answers-file template: the bundle brings
  `{{ _copier_conf.answers_file }}.jinja`.
- Copier reads the `!include` that a branch lacks as empty, so a copy of a branch would give half
  a project. A question's validator stops it with a first clause,
  `{% if 'issues_repo' not in _copier_answers %}`, whose message says to copy a release tag.

## What a stack template supplies

A stack template supplies these fixed names:

| File | Contract |
|---|---|
| `.github/actions/stack-gate/action.yaml` | The composite action that the `Gate` workflow runs on every PR into `develop`, `staging` or `main`, after its PR-source check and the checkout. It calls the stack's tools directly, never `make gate`. Without it, the `Gate` workflow fails. |
| `.claude/hooks/practices/registry.jq` | `kind($path)` returns the file's kind or `null`; `practices($ctx; $kind)` streams `{level, text}`, with level `stop` or `remind`, from the stack's practice modules beside it. `lib.jq` provides `edit_context`, the text helpers, and the reason form a skipped check gives (`reason_form`, `reason_steps`). |
| `.claude/hooks/stack/format.sh` | Runs after every Edit/Write with the hook payload on stdin. |
| `make gate` | The project's full local validation, which `/gate` runs. |

This template ships no `Makefile`. The stack template seeds the project's `Makefile`, which
includes the stack's make fragment, and that fragment must include this template's:

```make
include .claude/agentic.mk
```

`.claude/agentic.mk` gives `make claude` and `make help`. The project's `Makefile` includes only
the stack fragment, since a second include defines each target twice. The stack fragment must
describe each target on its rule line, as `gate: ## <description>`, for `make help` to list it.
It extends a target of `agentic.mk` only with a prerequisite or a variable set after the include,
never with a second recipe, which make warns about on every call.

The stack's rules go in `.claude/rules/`, beside `agentic.md` and `conventions.md`. One of them
lists the stack's skipped-check directives and the tools whose docs to read, which
`conventions.md` leaves to the stack.

Claude Code reads one shared project settings file, `.claude/settings.json`, and this template
renders it for every stack. A new stack adds its permissions and environment to
`template/.claude/settings.json.jinja` here, each line one that changes nothing in the other
stacks, as the `pip` deny changes nothing outside Python.
