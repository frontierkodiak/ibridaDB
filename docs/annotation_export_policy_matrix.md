# Annotation Export Policy Matrix (POL-655)

Date: 2026-03-02
Issue: POL-655

## Non-destructive versioning invariants

1. Annotation updates are represented by **inserting** replacement rows and linking supersession edges in `annotation_supersession`.
2. Active selection excludes superseded rows (`annotation_active_selection_v1`) rather than deleting history.
3. Delete operations are blocked on annotation lineage tables by migration-installed guardrail triggers.

## Policy matrix (v1 seed)

| Policy | Version | Strategy | Min trust rank | Allowed sources | Include conflict |
|---|---|---|---:|---|---|
| `human_first` | 1 | human > imported_dataset > model | 1 | human, model, imported_dataset | false |
| `model_first` | 1 | model > human > imported_dataset | 2 | model, human, imported_dataset | false |
| `hybrid` | 1 | human > model > imported_dataset (trust weighted) | 1 | human, model, imported_dataset | false |

## Deterministic selector behavior

`annotation_export_select_v1(policy_name, policy_version)` selects one annotation per `(subject_id, label)` with deterministic ordering:

1. source priority (from policy strategy)
2. trust rank (descending)
3. confidence score (descending, NULLS LAST)
4. annotation UUID (ascending tie-break)

Rejected rows and (by default policy config) conflict rows are excluded from candidates.

## Decision log

- **Default policy** remains `human_first/v1` to avoid regressions for consumer expectations where human-reviewed signals should dominate.
- `model_first/v1` is retained as an explicit alternative for model-centric analysis runs with stronger trust floor.
- `hybrid/v1` is retained for mixed-source exports where human guidance is still prioritized but model candidates are promoted earlier than imported rows.

## Migration/backfill strategy for existing consumers

1. Keep existing consumers on previous selection assumptions while introducing policy surfaces in parallel.
2. Backfill supersession edges only when a canonical replacement mapping is known.
3. For legacy labels lacking provenance/quality rows:
   - map to `source_kind='imported_dataset'` with explicit source version where possible,
   - assign conservative trust rank through existing trusted-selection semantics.
4. Switch consumers to `annotation_export_default_human_first_v1` first, then evaluate policy alternatives with explicit run receipts.

## Drift/conflict test strategy

- Verify superseded rows are absent from `annotation_active_selection_v1` while remaining queryable in history.
- Verify selector output changes deterministically when switching policy (`human_first` vs `model_first`).
- Verify conflict/rejected rows are excluded under default v1 policies.
- Verify delete guardrails remain active in migration verification scripts and CI schema checks.
