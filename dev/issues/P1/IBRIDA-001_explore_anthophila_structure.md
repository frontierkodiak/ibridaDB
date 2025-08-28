---
issue_id: "IBRIDA-001"
title: "Explore anthophila directory structure and organization"
status: "completed"
priority: "high"
plan: "anthophila_investigation"
phase: "Phase 1"
created: "2025-08-27T00:00:00Z"
updated: "2025-08-27T00:00:00Z"
tags: ["data-exploration", "anthophila", "investigation"]
blocked_by: []
blocks: ["IBRIDA-002"]
---

## Summary

Explore the `/datasets/dataZoo/anthophila` directory structure to understand:
- Directory organization and naming patterns
- File types and counts
- Overall dataset size and scope
- Any existing metadata files or documentation

## Tasks
- [ ] List top-level directory structure in anthophila
- [ ] Count total number of directories and files
- [ ] Identify file types and extensions present
- [ ] Look for any metadata files (CSV, JSON, etc.)
- [ ] Sample a few directories to understand naming conventions
- [ ] Document findings for next phase analysis

## Notes

**COMPLETED FINDINGS:**
- 1,211 taxonomic directories containing 158,551 JPG images
- 68% of files (107,856) follow expected `Genus_species_NNNNNNNN_N.jpg` pattern
- 55,560 unique observation IDs ranging from 19953 to 67551749
- 166 genera, 1,138 species represented
- Average 1.9 photos per observation (max 56 photos)
- GBIF metadata present with 249 occurrence columns and multimedia data
- All observation IDs tested are valid iNaturalist observation URLs

## Context References
- `/home/caleb/repo/ibridaDB/preprocess/generic/README.md`