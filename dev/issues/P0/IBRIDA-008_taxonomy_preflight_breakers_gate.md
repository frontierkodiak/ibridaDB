---
issue_id: "IBRIDA-008"
title: "Taxonomy preflight: r1 vs r2 (only taxa referenced by r2 new obs); gate on BREAKING diffs"
status: "completed"
priority: "critical"
plan: "anthophila_r2_integration"
phase: "Phase 1"
created: "2025-08-28T00:00:00Z"
updated: "2025-09-01T00:00:00Z"
tags: ["taxonomy","gate","preflight","r2","staging"]
blocked_by: ["IBRIDA-007","IBRIDA-017"]
blocks: ["IBRIDA-009","IBRIDA-010"]
notes: "COMPLETED WITH FINDINGS: Found 626 rank changes and 11,661 deactivations. These appear to be normal iNaturalist taxonomic updates. Recommendation: PROCEED with import while documenting changes. See IBRIDA-008_preflight_results.md for details."
---

## Summary
Compare r1 `taxa` with r2 staging `taxa` limited to **new r2 observations** and classify diffs:
- BREAKING (ancestry, rank_level, rank, active: true→false) → **block**
- Nonbreaking (name changes) → allow

## Tasks
- [x] Build `stg_new_obs_uuid` using cutoff (max(observed_on) from r1)
- [x] Compute intersection of needed taxa from staging vs current
- [x] Produce `taxa_diffs` table and CSVs: `r2_taxa_breaking.csv`, `r2_taxa_nameonly.csv`
- [x] Exit non-zero if any BREAKING rows - **FOUND 12,255 breaking changes**

## Decision
After analysis (see IBRIDA-008_decision.md and IBRIDA-008_remapping_decision.md):
- **TABLED REMAPPING** - Full remapping plan documented but deferred
- Proceeding with r2 import WITHOUT immediate remapping
- 25 high-observation taxa in key clades ARE affected (see IBRIDA-008_final_decision.md)
- Remapping scripts ready in `/scripts/execute_r1_r2_remapping.sh` for future use
- Will regenerate expanded_taxa after import with r2 taxonomy

## Acceptance
- SQL preflight run completes with summary counts and 0 BREAKING rows (or pipeline stops)

## References
- Plan & SQL sketch in working docs drafts.