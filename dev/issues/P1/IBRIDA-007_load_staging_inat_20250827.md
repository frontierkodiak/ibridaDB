---
issue_id: "IBRIDA-007"
title: "Load Aug-2025 iNat CSVs into staging schema stg_inat_20250827"
status: "completed"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 1"
created: "2025-08-28T00:00:00Z"
updated: "2025-09-01T00:00:00Z"
tags: ["staging","inat","csv","psql","copy"]
blocked_by: ["IBRIDA-017", "IBRIDA-026"]
blocks: ["IBRIDA-008","IBRIDA-009"]
notes: "COMPLETED: Used UNLOGGED tables + optimized PostgreSQL settings. Loaded 209M observations (3.3h), 370M photos (5.4h), 1M observers, 1.6M taxa. Total time ~8.5h vs 24+h previously."
---

## Summary
Create `stg_inat_20250827.{observations,photos,observers,taxa}` with `LIKE` and load CSVs, then `ANALYZE`.

## Acceptance
- Row counts match CSVs (± header)
- `ANALYZE` complete on all 4 tables

## Context
- Input path provided in user note; plan docs establish delta-import approach (observed_on > cutoff).