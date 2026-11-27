# From the agentic template: change the template, not this copy.
# The verdict on a PR's checks, which the merge guard and the status line both give. A pending
# check outweighs a gate not run, since it may be the gate running. A check counts by its newest
# run, as in `gh pr checks`: the head keeps the checks of every run, one cancelled by a later run
# included. Load it with: jq -L <this folder> 'import "pr-checks" as checks; checks::verdict'

# The check the rulesets require; the Gate workflow's read-draft passes on a draft too.
def gate: .workflowName == "Gate" and (.name | startswith("gate / "));

def verdict:
  [.statusCheckRollup // [] | group_by([.workflowName, .name, .context])[] | max_by(.startedAt)
    | {gate: gate,
      conclusion: (if .__typename == "StatusContext" then .state
        elif .status == "COMPLETED" then .conclusion else "PENDING" end)}] as $c
  | if $c == [] then "no checks"
    elif any($c[].conclusion; IN("SUCCESS", "NEUTRAL", "SKIPPED", "PENDING", "EXPECTED") | not) then "checks failed"
    elif any($c[].conclusion; IN("PENDING", "EXPECTED")) then "checks pending"
    elif any($c[]; .gate and .conclusion == "SUCCESS") then "checks passed"
    else "gate not run" end;
