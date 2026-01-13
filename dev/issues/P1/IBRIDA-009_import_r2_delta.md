---
issue_id: "IBRIDA-009"
title: "Import r2 delta (obs/photos/observers + new taxa) with idempotent upserts"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Phase 2"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["r2","delta","upsert","etl","psql"]
blocked_by: ["IBRIDA-008","IBRIDA-007"]
blocks: ["IBRIDA-010","IBRIDA-016","IBRIDA-021"]
notes: "Tag rows with origin='inat', release='r2', version='20250827'. No mutation of r1 data."
---

## Summary
Upsert new r2 observations and their photos; left anti-merge observers; insert only new taxa ids. Record `releases` row later.

## Acceptance
- Counts match staging filters; re-run is a no-op

## Context
- Detailed SQL outlined in master plan draft (D.5).