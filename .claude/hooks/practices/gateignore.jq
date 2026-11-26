# From the agentic template: change the template, not this copy.
# The practice of the Gate workflow's skip lists, whatever the stack: guard.sh asks this layer
# before the stack's registry. STOP: an edit that adds a pattern without a reason in the form
# conventions.md gives on the `#` lines directly above it. A `!` pattern runs more checks, so it
# needs none.
include "lib";

def kind($path):
  if $path | test("/\\.github/(gate-checks/)?gateignore$") then "gateignore" else null end;

# The `#` lines directly above line $at, without their `#`, one per line.
def comment_above($lines; $at):
  ($lines[:$at] | reverse) as $up
  | (first(range(0; $up | length) | select($up[.] | test("^#") | not)) // ($up | length)) as $n
  | $up[:$n] | reverse | map(sub("^#\\s?"; "")) | join("\n");

# In .gitignore, a line that is blank, starts with `#` or starts with `!` skips no check.
def skips: test("^(\\s*$|#|!)") | not;

def practices($ctx; $kind):
  [$ctx.added[] | select(.line | skips) | select(comment_above($ctx.new; .at) | reason_form | not)
   | "- `\(.line | short)`"]
  | select(length > 0)
  | {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
      + " (.claude/rules/conventions.md). The Gate workflow skips every check of a PR that"
      + " changes only paths on its skip lists, so each pattern added to \($ctx.rel) loosens CI."
      + " Keep a pattern only if no check reads the paths it matches.\n"
      + reason_steps("adding the pattern"; "the pattern";
          "the tools that .github/workflows/gate-checks.yaml runs")
      + "The reason goes on the `#` lines directly above the pattern: .gitignore has no comment"
      + " on a pattern's own line.\n" + join("\n"))};
