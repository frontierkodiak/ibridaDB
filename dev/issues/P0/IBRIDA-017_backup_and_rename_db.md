---
issue_id: "IBRIDA-017"
title: "Safe backup of ibrida-v0-r1, test restore, then rename DB to ibrida-v0 and update references"
status: "open"
priority: "critical"
plan: "anthophila_r2_integration"
phase: "Phase 0"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["backup","admin","db-rename","references","safety"]
blocked_by: []
blocks: ["IBRIDA-007","IBRIDA-008","IBRIDA-009","IBRIDA-018"]
notes: "Renaming occurs only after verified backup. Update CLAUDE.md and non-archival scripts to use ibrida-v0."
---

## Summary
Create a custom-format dump (`.dump`) of `ibrida-v0-r1`, verify checksum + pg_restore listing, attempt a scratch restore, then **rename** DB to `ibrida-v0`. Update in-repo references everywhere **except** archival wrappers (`dbTools/ingest/export v0/r0,r1`).  

## Tasks
- [ ] Run `dbTools/admin/backup_ibrida_v0r1.sh` to produce `/datasets/ibrida-data/backups/…/ibrida-v0-r1.dump`
- [ ] Optional: restore into `ibrida-v0-r1_scratch` to validate
- [ ] Terminate sessions & `ALTER DATABASE "ibrida-v0-r1" RENAME TO "ibrida-v0"`
- [ ] Update references (CLAUDE.md, scripts) excluding archival wrappers; commit on branch
- [ ] Sanity psql checks on `ibrida-v0`

## Acceptance
- Verified dump and successful scratch restore
- DB now visible as `ibrida-v0`
- Reference updates committed on branch (diff isolates archival dirs)

## Context
- Admin helpers added in prior ops step; CLAUDE.md & tree show current DB naming.