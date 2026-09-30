---
description: Enumerate candidate initiatives in this repo and rank by Leverage = (V*D*C)/E.
argument-hint: "[optional theme]"
---
Find the highest-leverage initiatives in THIS repo. Read the code, issues, and tests first.

Score each candidate with the leverage skill: Leverage = (V * D * C) / E, each factor 1-5.
Apply the hard gate BEFORE ranking: drop anything with C <= 2, or E = 5 unless V = 5.

Output a ranked table: Initiative | V | D | C | E | Leverage | one-line why.
Then name the single top pick and its first concrete step (describe it; this engine does not apply changes). No hedged option-lists — recommend.
Constrain to $ARGUMENTS if given.
