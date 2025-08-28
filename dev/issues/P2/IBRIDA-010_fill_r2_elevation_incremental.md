---
issue_id: "IBRIDA-010"
title: "Fill elevation for r2 delta only (work-queue view + optional geohash cache)"
status: "open"
priority: "normal"
plan: "anthophila_r2_integration"
phase: "Phase 2"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["elevation","dem","performance","cache"]
blocked_by: ["IBRIDA-009"]
blocks: []
notes: "Define view elevation_todo; process with SELECT ... FOR UPDATE SKIP LOCKED; optional geohash7 cache."
---

## Acceptance
- `SELECT COUNT(*) FROM elevation_todo` → 0 after job
- Spot checks confirm elevations populated