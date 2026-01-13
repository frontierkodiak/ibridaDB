---
issue_id: "IBRIDA-026"
title: "Implement fast Polars-based ingestion pipeline for iNaturalist CSVs"
status: "in_progress"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 1"
created: "2025-08-31T00:00:00Z"
updated: "2025-08-31T00:00:00Z"
tags: ["ingestion","performance","polars","staging","optimization"]
blocked_by: []
blocks: ["IBRIDA-007"]
notes: "Critical performance optimization to reduce ingestion from 26+ hours to 2-3 hours. Enables monthly automated updates."
---

## Summary
Replace slow PostgreSQL COPY with Polars streaming pipeline using UNLOGGED staging tables. Expected 10-20x speedup for massive CSV ingestion.

## Tasks
- [ ] Create Polars-based fast ingestion script with chunked streaming
- [ ] Implement UNLOGGED staging table creation
- [ ] Update Docker Compose with PostgreSQL bulk loading optimizations
- [ ] Test with Aug-2025 data to verify performance gains
- [ ] Document new ingestion workflow

## Technical Approach
1. **Polars for heavy lifting**: Read, validate, transform CSVs in memory
2. **UNLOGGED staging tables**: Bypass WAL for initial load
3. **Chunked streaming**: Handle 41GB+ files without memory issues
4. **PostgreSQL tuning**: Optimize checkpoint, WAL, and buffer settings
5. **Final INSERT**: Move from unlogged staging to permanent tables

## Acceptance
- Aug-2025 CSVs loaded in under 3 hours (vs current 26+ hours)
- No data loss or corruption
- Script is reusable for future monthly ingestions
- IBRIDA-007 can proceed with staged data

## Performance Targets
- observations (23GB): ~15-30 mins
- photos (41GB): 1-2 hours  
- taxa (174MB): ~30 secs
- observers (24MB): ~10 secs