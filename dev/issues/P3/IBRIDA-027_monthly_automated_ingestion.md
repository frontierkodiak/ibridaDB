---
issue_id: "IBRIDA-027"
title: "Automate monthly iNaturalist data ingestion with ntfy notifications"
status: "open"
priority: "low"
plan: "future_automation"
phase: "Enhancement"
created: "2025-08-31T00:00:00Z"
updated: "2025-08-31T00:00:00Z"
tags: ["automation","cron","ingestion","ntfy","monthly"]
blocked_by: ["IBRIDA-026"]
blocks: []
notes: "Low priority enhancement for future consideration. Would enable automatic monthly updates from iNaturalist dumps."
---

## Summary
Create cron job to automatically download and ingest monthly iNaturalist data dumps, with ntfy server notifications to polliserve0.

## Proposed Implementation
1. **Monthly cron job** (run on 2nd of each month after iNat publishes)
2. **Download latest dump** from iNaturalist AWS S3
3. **Run fast Polars ingestion** (from IBRIDA-026)
4. **Send ntfy notification** to polliserve0 channels:
   - On start: "Starting iNat ingestion for [Month Year]"
   - On success: "✓ Ingested X observations, Y photos in Z minutes"
   - On failure: "✗ Ingestion failed: [error details]"

## Benefits
- Keep database continuously fresh with latest observations
- No manual intervention required
- Fast enough with Polars optimization (~2-3 hours)
- Existing ntfy helper functions in dbTools can be reused

## Acceptance
- Fully automated monthly updates
- Reliable notifications via ntfy
- Error handling and retry logic
- Logs preserved for debugging