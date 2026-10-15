# rules.jq — ACC v0.1 rules, mechanically checked. Input: the file as one raw string.
# Use:  jq -R -s -L agent-context/v0.1 -f agent-context/v0.1/rules.jq CLAUDE.md                                   (Core: A1-A7, A10)
#       jq -R -s -L agent-context/v0.1 --slurpfile ckb ckb.json --rawfile human human.md -f rules.jq CLAUDE.md   (Standard: + A8, A9)
# Output: array of violation strings, each starting with its rule code. Empty = conformant.
include "acc";
def strip_comments: gsub("<!--[\\s\\S]*?-->"; "");
def strip_fences: gsub("```[\\s\\S]*?```"; "");
def words: [splits("[ \t\n]+") | select(length > 0)] | length;
. as $raw
| ($raw | gsub("\r"; "") | strip_comments) as $body
| ($body | split("\n")) as $lines
| ([$lines[] | select(test("^## ")) | sub("^## "; "") | sub("\\s+$"; "")]) as $secs
| ([$lines[] | select(length > 0)] | first // "") as $first
| ([$raw | scan("<!-- ckb-ac:begin[^>]*-->")]) as $begins
| ([$raw | scan("<!-- ckb-ac:end -->")]) as $ends
| (($ARGS.named.ckb // [null])[0]) as $art
| [
    # A1 structure: H1 first, then exactly the six sections in order
    (if ($first | test("^# Agent context — \\S")) | not then "A1 first line must be '# Agent context — <repo>'" else empty end),
    (if $secs != sections then "A1 sections must be exactly, in order: \(sections | join(" | "))" else empty end),
    # A2 budget
    (($body | strip_fences | words) as $w | if $w > 400 then "A2 \($w) words > 400" else empty end),
    # A3 one fact per bullet: no nested bullets, no bullet over 50 words
    ($lines[] | select(test("^\\s+[-*] ")) | "A3 nested bullet: \(.[0:60])"),
    ($lines[] | select(test("^- ")) | select(words > 51) | "A3 bullet over 50 words: \(.[0:60])"),
    # A4 Non-negotiables are firm: no hedging
    (($body | capture("## Non-negotiables\\n(?<s>[\\s\\S]*?)(\\n## |$)").s // "") | select(test("\\b(maybe|might|probably|perhaps|try to|consider|ideally)\\b"; "i")) | "A4 hedged wording in Non-negotiables"),
    # A5 no secrets
    (select($body | test("AKIA[0-9A-Z]{12}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|(password|secret|token|api[_-]?key)\\s*[:=]\\s*\\S"; "i")) | "A5 secret-looking value"),
    # A6 never instruct an agent to fetch-and-run or to skip a safety check
    (select($body | test("(curl|wget)[^|\\n]*\\|\\s*(ba|z)?sh|--dangerously|--no-verify|skip (the )?(confirmation|review|tests)"; "i")) | "A6 fetch-and-run or safety-skip instruction"),
    # A7 determinism: no dates, LF only, no tabs, no trailing whitespace
    (select($body | test("\\b[0-9]{4}-[0-9]{2}-[0-9]{2}\\b")) | "A7 contains a date"),
    (select($raw | test("\r")) | "A7 CR line endings"),
    (select($raw | test("\t")) | "A7 tab character"),
    ($lines[] | select(test("[ ]+$")) | "A7 trailing whitespace: \(.[0:40])"),
    # A10 no template residue
    (select($body | test("\\[(P|H)\\]|TODO\\(human\\)")) | "A10 template placeholder left in the file"),
    # A8 marker integrity (only when a marker is present, or always at Standard level)
    (if ($begins | length) > 0 or ($ends | length) > 0 or $art != null then
       (if ($begins | length) != 1 or ($ends | length) != 1 then "A8 need exactly one ckb-ac:begin and one ckb-ac:end marker"
        elif ($raw | index($begins[0])) > ($raw | index($ends[0])) then "A8 ckb-ac:end before ckb-ac:begin"
        elif ($begins[0] | test("^<!-- ckb-ac:begin acc=0\\.1 ckb=0\\.[0-9]+ commit=[0-9a-f]{40} -->$") | not) then "A8 malformed marker: \($begins[0])"
        else empty end)
     else empty end),
    # A9 (Standard) the region equals the normative projection of the artifact at that commit
    (if $art != null then
       (($raw | capture("commit=(?<c>[0-9a-f]{40})").c // "") as $c
        | if $c != $art.repo.commit_sha then "A9 marker commit \($c[0:12]) is not the artifact commit \($art.repo.commit_sha[0:12])"
          elif ($raw | rtrimstr("\n")) != ($art | acc_project($ARGS.named.human // "")) then "A9 content differs from the projection of ckb.json (edit .ckb/agent-context.human.md, not the generated region)"
          else empty end)
     else empty end)
  ]
