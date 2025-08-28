---
issue_id: "IBRIDA-002"
title: "Analyze anthophila filename patterns for iNat ID extraction"
status: "completed"
priority: "high"
plan: "anthophila_investigation"
phase: "Phase 1"
created: "2025-08-27T00:00:00Z"
updated: "2025-08-27T00:00:00Z"
tags: ["data-analysis", "anthophila", "filename-parsing"]
blocked_by: ["IBRIDA-001"]
blocks: ["IBRIDA-003"]
---

## Summary

Analyze filename patterns in anthophila dataset to:
- Confirm if filenames follow `Genus_species_NNNNNNNN_N.jpg` pattern
- Extract numeric IDs that may correspond to iNaturalist observation IDs
- Develop parsing logic to reliably extract these IDs
- Test hypothesis that these IDs correspond to `photos.photo_id` or observation IDs

## Tasks
- [ ] Sample filenames from multiple directories
- [ ] Identify consistent naming patterns
- [ ] Extract numeric components from filenames
- [ ] Test a few IDs against iNaturalist URLs (e.g., inaturalist.org/observations/ID)
- [ ] Create script to parse all filenames and extract potential iNat IDs
- [ ] Generate statistics on filename patterns

## Notes

**COMPLETED ANALYSIS:**
- Confirmed: 68% of files (107,856/158,551) follow `Genus_species_NNNNNNNN_N.jpg` pattern
- Successfully extracted 55,560 unique observation IDs
- Pattern is highly reliable for iNaturalist observation ID extraction  
- All sampled IDs correspond to valid iNaturalist observation URLs
- Ready to proceed with database duplicate checking

## Context References
- `/home/caleb/repo/ibridaDB/preprocess/generic/README.md`
- Example: `https://www.inaturalist.org/observations/10421352`