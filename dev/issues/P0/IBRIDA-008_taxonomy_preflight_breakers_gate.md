---
issue_id: "IBRIDA-008"
title: "Taxonomy preflight: r1 vs r2 (only taxa referenced by r2 new obs); gate on BREAKING diffs"
status: "open"
priority: "critical"
plan: "anthophila_r2_integration"
phase: "Phase 1"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["taxonomy","gate","preflight","r2","staging"]
blocked_by: ["IBRIDA-007","IBRIDA-017"]
blocks: ["IBRIDA-009","IBRIDA-010"]
notes: "Proceed only if no BREAKING items (ancestry/rank_level/rank changes or deactivations) for taxa referenced by r2 new observations."
---

## Summary
Compare r1 `taxa` with r2 staging `taxa` limited to **new r2 observations** and classify diffs:
- BREAKING (ancestry, rank_level, rank, active: true→false) → **block**
- Nonbreaking (name changes) → allow

## Tasks
- [ ] Build `stg_new_obs_uuid` using cutoff (max(observed_on) from r1)
- [ ] Compute intersection of needed taxa from staging vs current
- [ ] Produce `taxa_diffs` table and CSVs: `r2_taxa_breaking.csv`, `r2_taxa_nameonly.csv`
- [ ] Exit non-zero if any BREAKING rows

## Acceptance
- SQL preflight run completes with summary counts and 0 BREAKING rows (or pipeline stops)

## References
- Plan & SQL sketch in working docs drafts.