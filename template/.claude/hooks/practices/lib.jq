# From the agentic template: change the template, not this copy.
# Shared by every practice module: what one edit changes, plus text helpers.
# Whole-file set difference on trimmed lines, not a diff: a line that only moves or changes
# indentation is neither added nor removed, so refactoring old code never re-judges it.

def lines: split("\n");

# The file as the edit will leave it. $old_file is the content on disk ("" for a new file).
def new_file($old_file):
  .tool_input as $t
  | if ($t.content | type) == "string" then $t.content
    elif ($t.edits | type) == "array" then
      reduce $t.edits[] as $e ($old_file; split($e.old_string) | join($e.new_string))
    elif ($t.old_string // "") == "" then $t.new_string // ""
    else $old_file | split($t.old_string) | join($t.new_string // "")
    end;

def line_set: reduce .[] as $line ({}; .[$line] = true);

def trimmed: sub("^\\s+"; "") | sub("\\s+$"; "");

# The context every module's check($ctx) reads: {rel, old, new, added: [{line, above, at}], removed};
# `at` is the line's index in `new`.
def edit_context($old_file; $rel):
  ($old_file | lines) as $old
  | (new_file($old_file) | lines) as $new
  | ($old | map(trimmed) | line_set) as $old_set
  | ($new | map(trimmed) | line_set) as $new_set
  | {
      rel: $rel, old: $old, new: $new,
      added: [range(0; $new | length) as $i | select($old_set[$new[$i] | trimmed] | not)
              | {line: $new[$i], above: (if $i > 0 then $new[$i - 1] else "" end), at: $i}],
      removed: [$old[] | select(trimmed as $line | $new_set[$line] | not)]
    };

def has($re): test($re; "i");
def short: sub("^\\s+"; "") | if length > 90 then .[:87] + "..." else . end;
def durability:
  "Will it still be true, and still make sense, in a year, to a reader who never saw today's"
  + " change? Say what holds, not what changed: no versions it moved from, no past bugs, no"
  + " \"now\", \"no longer\", \"since\" or \"used to\".";
