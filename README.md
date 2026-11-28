# template-agentic

A [Copier](https://copier.readthedocs.io/) template for the language-neutral half of an agentic
coding setup: the Claude Code hooks, rules, skills and agents, the issue → worktree → session
task workflow, and the CI workflows. A stack template, such as `template-python-service`, carries
it inside each of its releases and fills its plug-in points for one stack, so a project applies
the stack template only.

## Bundle into a stack template

A stack template takes this template in four steps:

1. Apply this template to the stack template's own repository, and make its `renovate.json`
   extend `renovate/base`:

   ```bash
   uvx copier copy https://github.com/BorjaElizalde/template-agentic.git .
   ```

2. Release from the `Build` workflow on each merge to `main`, with `contents: write`, by running
   `release.sh` as its header says. `GITHUB_TOKEN` may push the tag: GitHub refuses a workflow
   file at the root `.github/workflows/` only.
3. Open the stack template's `copier.yaml` with `!include agentic/copier.yaml` and `---`, then
   give its own settings and questions. Copier joins the two documents' `_skip_if_exists` lists,
   and where both name `_answers_file` or a question, the stack template's wins. So list only its
   own seeded files, name its own `_answers_file`, and give its questions names that this
   template does not use, except `gate_paths_ignore`, which it gives a default. They come after
   this template's questions, so they and its files may read this template's answers. Add no
   answers-file template: the bundle brings one.
4. Start the validator of a question that has no default with
   `{% if 'issues_repo' not in _copier_answers %}`, whose message says to copy a release tag. It
   stops a copy of a branch.

## What a stack template supplies

A stack template's `template/` supplies each file that this template's files call but do not
ship, such as the make fragment that defines `gate`. The file it plugs into states its contract.
The stack's own rules go in its `template/.claude/rules/`, and hold what this template's rules
and skills leave to a stack.

Claude Code reads one project settings file, `.claude/settings.json`, so this template renders it
for every stack. A new stack adds its permissions and environment to it in this repository, each
line one that changes nothing in the other stacks, as the `pip` deny changes nothing outside
Python. A project's own settings go in `.claude/settings.project.json`, which this template seeds
once and its launchers load.
