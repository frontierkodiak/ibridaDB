---
issue_id: "IBRIDA-013"
title: "Materialize anthophila_flat/ and insert kept items into media"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 3"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["fs","copy","hardlink","media","insert"]
blocked_by: ["IBRIDA-012","IBRIDA-006"]
blocks: ["IBRIDA-021","IBRIDA-022","IBRIDA-023"]
notes: "Use canonical file:// URIs; include sidecar JSONB with provenance (original_path, source_tag, sha256). License='unknown'."
---

## Summary
Copy or hardlink all `keep_flag=true` items into `anthophila_flat/` and insert corresponding rows into `media` with dataset='anthophila', release='r2'.

## Acceptance
- Flat dir count equals kept set; insert OK with unique(sha256_hex) satisfied