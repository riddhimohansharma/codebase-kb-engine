# acc.jq — ACC v0.1 normative projection (library): CKB v0.3 artifact (+ optional human lines) -> agent-context body (CLAUDE.md / AGENTS.md).
# acc_project($human): input = artifact, $human = contents of .ckb/agent-context.human.md ("" if none). Called by project.jq and rules.jq (A9).
# Human file: lines "- text" under any of the six section headings; they are appended after the projected lines of that section.
# Budget: at most 400 words. Lines are admitted by section order, then by confidence (confirmed first), then by id; the rest is dropped.
def sections: ["Non-negotiables", "Shape", "Commands", "Changing X obligates Y", "Traps", "Before you say you're done"];
def rank: {confirmed: 0, inferred: 1, unknown: 2}[.confidence // "unknown"];
def cite: (.provenance // [])[0] | if . == null then "" else " (`\(.path):\(.line)`)" end;
def words: [splits("[ \t\n]+") | select(length > 0)] | length;
def bt: "`" + . + "`";

def acc_project($human):
($human // "") as $h
| . as $a
| ($a.repo.key // ($a.repo.url | sub("^https://"; "") | ascii_downcase)) as $key
| ($key | split("/") | last) as $name
# human lines per section
| (reduce ($h | split("\n"))[] as $l ({cur: null, out: {}};
     if ($l | test("^## ")) then .cur = ($l | sub("^## "; "") | sub("\\s+$"; ""))
     elif ($l | test("^- ")) and .cur != null and (.cur as $c | sections | index($c) != null) then .cur as $c | .out[$c] += [($l | sub("^- "; "") | sub("\\s+$"; ""))]
     else . end) | .out) as $hum
| def proj($sec):
    if $sec == "Non-negotiables" then
      ([$a.entities.invariants[]? | select(.kind == "constraint")] | sort_by([rank, .id]) | map(.statement + cite))
      + ((($a.repo_profile.generated_globs // []) + ($a.repo_profile.vendored_globs // [])) | unique | if length > 0 then ["Do not edit generated or vendored files: " + (map(bt) | join(", ")) + "."] else [] end)
    elif $sec == "Shape" then
      [$a.entities.components[]? | select(.module_id != ".")] | sort_by(.module_id) | .[0:8]
      | map((.module_id | bt) + ": " + .kind + (if .layer then ", " + .layer else "" end))
    elif $sec == "Commands" then
      [$a.entities.commands[]?] | sort_by([({build:0,test:1,lint:2,format:3,run:4,migrate:5,deploy:6,other:7}[.kind]), .id])
      | map((.command | bt) + " (" + .kind + (if (.cwd // ".") != "." then ", in " + (.cwd | bt) else "" end) + ")")
    elif $sec == "Changing X obligates Y" then
      [$a.entities.invariants[]? | select(.kind == "obligation")] | sort_by([rank, .id])
      | map(((.applies_to // []) | map(bt) | join(", ")) + " → " + ((.obligates // []) | map(bt) | join(", ")) + ": " + .statement)
    elif $sec == "Traps" then
      [$a.entities.invariants[]? | select(.kind == "trap")] | sort_by([rank, .id]) | map(.statement + cite)
    else
      ([$a.entities.commands[]? | select(.kind == "test" or .kind == "lint")] | sort_by(.id) | map(.command | bt)) as $c
      | if ($c | length) > 0 then ["These pass: " + ($c | join(", ")) + "."] else [] end
    end;
  ([sections[] as $s | (proj($s) + ($hum[$s] // [])) as $ls | {s: $s, lines: $ls}]) as $all
| ("# Agent context — " + $name) as $h1
| ("<!-- ckb-ac:begin acc=0.1 ckb=\($a.ckb_version) commit=\($a.repo.commit_sha) -->") as $begin
| "<!-- ckb-ac:end -->" as $end
| ([ ($a.repo_profile.languages // [])[] | .name ] | .[0:2] | map(ascii_downcase)) as $langs
| ($a.repo_profile.taxonomy // {}) as $t
| ("A " + (if ($langs | length) > 0 then ($langs | join(" and ")) + " " else "" end) + "repository"
   + ([ ($t.domain // empty | "domain " + .), ($t.system // empty | "system " + .), ($t.lifecycle // empty) ] | if length > 0 then " (" + join(", ") + ")" else "" end) + ".") as $desc
# budget: admit lines in order until 400 words
| ((($h1 + " " + $desc) | words) + 12 + 18) as $fixed   # H1, description, six "## Section" headings, and room for six "- None recorded."
# admission priority (what an agent can least afford to lose first); output order stays canonical
| ["Commands", "Before you say you're done", "Non-negotiables", "Changing X obligates Y", "Traps", "Shape"] as $prio
| (reduce ($prio[] as $p | $all[] | select(.s == $p) | .s as $s | .lines[] | {s: $s, l: .}) as $x ({used: $fixed, keep: []};
     ("- " + $x.l | words) as $w | if .used + $w <= 400 then .used += $w | .keep += [$x] else . end)) as $b
| [$begin, $h1, "", $desc, ""]
  + ([sections[] as $s | ["## " + $s] + ([$b.keep[] | select(.s == $s) | "- " + .l] | if length == 0 then ["- None recorded."] else . end) + [""]] | add)
  + [$end]
| join("\n");
