---
issue_id: "IBRIDA-014"
title: "Verify anthophila ingest: counts, FKs, orphan scan, origin/release"
status: "open"
priority: "normal"
plan: "anthophila_r2_integration"
phase: "Phase 3"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["verification","qa","sql"]
blocked_by: ["IBRIDA-013"]
blocks: []
notes: "Automate standard checks and write a small summary file under dev/working_docs/anthophila_ingest/"
---

## Acceptance
- No FK violations; no orphan `media` rows; counts match manifest; origin/version/release set correctly