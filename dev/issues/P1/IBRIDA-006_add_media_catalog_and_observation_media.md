---
issue_id: "IBRIDA-006"
title: "Add generic media catalog (URIs) + observation_media junction; do not alter iNat photos"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 2"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["schema","ddl","media","uri","sidecar","migration"]
blocked_by: ["IBRIDA-017"]
blocks: ["IBRIDA-013","IBRIDA-021","IBRIDA-022","IBRIDA-023","IBRIDA-024"]
notes: "Keep invariant: photos == iNat images with non-null photo_id. Anthophila and other non-iNat assets go into `media` with file://, b2://, s3://, https:// URIs."
---

## Summary
Create `media(media_id BIGSERIAL PK, dataset, release, source_tag, uri, sha256_hex, phash_64, width_px, height_px, mime_type, file_bytes, captured_at, sidecar JSONB, license, created_at)` + `observation_media(observation_uuid, media_id, role)`; unique on `(uri)` and `(sha256_hex)`.

## Tasks
- [ ] Apply DDL migration; indexes on `(dataset,release)` and `(sha256_hex)`
- [ ] Create public view `public_media` excluding unknown/restricted license
- [ ] Smoke-test inserts & uniqueness

## Acceptance
- Tables & view exist; basic insert/select passes; iNat `photos` untouched

## Context
- Design decision captured in working plan and drafts (use `media`, reserve `photos` for iNat).