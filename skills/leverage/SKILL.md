---
name: leverage
description: Leverage-scoring rubric used only by codebase-kb-engine's /hunt command. Never load for general prioritization outside that command.
disable-model-invocation: true
---
# Leverage scoring

Score every candidate: Leverage = (V * D * C) / E

- V — Value: impact if it lands. 1 trivial ... 5 transformational.
- D — Durability: how long the value compounds. 1 one-off ... 5 permanent moat.
- C — Confidence: probability it works as scoped. 1 speculative ... 5 near-certain.
- E — Effort: total cost to ship. 1 hours ... 5 multi-week.

Hard gates, applied before ranking: drop if C <= 2 (too speculative) or E = 5 (too costly) unless V = 5.
Rank survivors by Leverage descending. Always end with a single recommended top pick and its first concrete step — never present the ranking alone.
