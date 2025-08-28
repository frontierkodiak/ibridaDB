---
issue_id: "IBRIDA-011"
title: "Build anthophila_manifest.csv with sha256, pHash, size, ID-type guess"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 3"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["anthophila","manifest","hashing","pHash","scanner"]
blocked_by: ["IBRIDA-017"]
blocks: ["IBRIDA-012","IBRIDA-013"]
notes: "Output columns include: asset_uuid, original_path, flat_name, scientific_name_norm, id_core, id_type_guess, width, height, sha256, phash, source_tag, license_guess, keep_flag."
---

## Summary
Write a scanner to walk the anthophila tree, compute metadata and build a CSV manifest for the dedup & ingest steps.

## Acceptance
- 100% rows parse; dimensions/hashes present; early size histogram written