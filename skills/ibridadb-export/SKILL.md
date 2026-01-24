---
name: "ibridadb-export"
description: "Run ibridaDB export wrappers to produce training CSVs (and related artifacts) from a specific release DB."
---

# ibridadb-export

Use this skill when generating dataset exports from ibridaDB.

## Preconditions
- Target DB exists (e.g., `ibrida-v0-r2`).
- `expanded_taxa` is up to date for that DB.
- If elevation is required, `observations.elevation_meters` is populated for the relevant rows.

## Procedure
1) **Pick a wrapper**
   - Look under `dbTools/export/v0/r1/` for existing configs.
   - For r2, copy/adjust wrappers as needed (avoid modifying r1 wrappers).

2) **Set environment**
   - DB name, export params (region, clade/metaclade, min obs, max rn).
   - Example wrappers already set defaults; review before running.

3) **Run export**
   - `dbTools/export/v0/r1/<wrapper>.sh`
   - Outputs land under `/datasets/ibrida-data/exports` (or wrapper-specific path).

4) **Validate**
   - Check export CSV counts.
   - Verify summary files and schema expectations.

## Notes
- Do not break r1 reproducibility.
- Keep wrappers single-purpose; avoid large multi-branch scripts.
