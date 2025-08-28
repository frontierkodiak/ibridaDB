---
issue_id: "IBRIDA-012"
title: "Deduplicate anthophila (Pass A: ID-based; Pass B: hash-based vs iNat)"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 3"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["dedup","hash","matching","photos","observations"]
blocked_by: ["IBRIDA-011","IBRIDA-006","IBRIDA-009"]
blocks: ["IBRIDA-013","IBRIDA-020"]
notes: "Ensure we probe the right domain: if filenames are observation IDs, do not join to photos.photo_id."
---

## Summary
Determine duplicates by (a) matching id_core against the correct domain (observation vs photo) and (b) sha256/pHash collisions versus iNat primaries; write reasons.

## Acceptance
- CSV with `{filename, dup_reason ∈ {obs_id, photo_id, sha256, phash}, matched_key}`
- Summary stats consistent with prior sampling