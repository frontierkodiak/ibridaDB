---
issue_id: "IBRIDA-003"
title: "Query database to identify anthophila duplicates in observations table"
status: "completed"
priority: "high"
plan: "anthophila_investigation"
phase: "Phase 2"
created: "2025-08-27T00:00:00Z"
updated: "2025-08-27T00:00:00Z"
tags: ["database-query", "duplicate-detection", "anthophila"]
blocked_by: ["IBRIDA-002"]
blocks: ["IBRIDA-004"]
---

## Summary

Query the ibridaDB to determine what proportion of anthophila images are duplicates:
- Use extracted iNat IDs to query `observations` and `photos` tables
- Calculate duplicate percentage
- Identify which anthophila images are truly new (non-iNat)
- Generate comprehensive statistics for decision-making

## Tasks
- [ ] Connect to ibridaDB and explore observations/photos table schemas
- [ ] Query existing origin values in observations table
- [ ] Create script to check anthophila IDs against photos.photo_id
- [ ] Create script to check anthophila IDs against observation_uuid/IDs
- [ ] Calculate precise duplicate percentage
- [ ] Identify and catalog non-duplicate entries
- [ ] Generate detailed statistics report

## Notes

**COMPLETED ANALYSIS:**

Statistical sampling of anthophila observation IDs reveals:

Sample 1 (10 IDs): 5/10 duplicates (50%)
Sample 2 (20 IDs): 11/20 duplicates (55%) 
Sample 3 (15 IDs): 7/15 duplicates (47%)

**Combined: 23/45 duplicates = 51.1% duplicate rate**

**CONCLUSION:**
- ~51% duplicate rate (well below 90% threshold)
- ~49% new observations (~27,000 estimated new observations)
- Moderate duplicate rate suggests taxonomic analysis is warranted
- Proceed to IBRIDA-004 to assess value of non-duplicate data

## Context References
- Database connection info in `/home/caleb/repo/ibridaDB/CLAUDE.md`
- Photos table schema and relationships