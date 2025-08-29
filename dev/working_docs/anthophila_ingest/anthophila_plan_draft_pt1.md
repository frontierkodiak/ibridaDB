Below is a **milestone‑based, issue‑driven plan** to bring the `anthophila` dataset into **ibridaDB** and make it first‑class in **ibrida.generator**. I’ve made concrete decisions where possible, flagged risks, and left a short “Open Questions” section at the end for anything that truly requires your preference.

I’m anchoring the plan to the current ibridaDB/ibrida code and documentation you shared so the team can trace design choices. Where I cite the repo/export docs, I include inline markers so folks can jump to the right place in your internal docs dump.

---

## Project narrative

**Goal.** Safely ingest expert‑labeled bee images from `anthophila` into **ibridaDB**’s `observations` (+ media) so that they’re available to **ibrida.generator** for training dataset builds, with clean deduplication against iNat, clear provenance, and minimal disruption to the current export/generator pipelines.

**Why now.** Your local agent’s analysis projects \~27k net‑new, expert‑labeled observations across 1,139 species (with notable rare taxa), below the 90% “not worthwhile” duplicate threshold—so the gain is meaningful and aligned with Polli’s product focus on bees.

**Guiding principles.**

* **Fail‑fast on value**: confirm the net‑new count with a rigorous duplicate pass before heavy lift.
* **Non‑destructive integration**: use a new **release** (“r2”) tag to keep v0r1 reproducible; rely on `origin` to distinguish `anthophila` rows at query time. Your schema already carries `origin`, `version`, `release` on all core tables, populated by existing ingestion scripts. &#x20;
* **Minimal schema churn**: prefer compatibility shims and adapters over schema changes, but fix hard blockers (see “Photos table” below).
* **Make generator “storage‑agnostic”**: formalize a local‑file media provider alongside the current S3 downloader so hybrid datasets (images on disk + labels.h5) work for both iNat and anthophila. The generator architecture and docs already assume a source index → downloader → preprocessor → writer flow and hybrid outputs. &#x20;

---

## Key constraints & facts from the code/docs

* **Core schema (v0r1).**
  `observations` carries: `observation_uuid`, `observer_id`, `latitude`, `longitude`, `positional_accuracy`, `taxon_id`, `quality_grade`, `observed_on`, `anomaly_score`, `geom`, **plus** `origin`, `version`, `release` (and sometimes `elevation_meters`). In structure.sql, `observation_uuid` is **NOT NULL**. We will not have iNat UUIDs for anthophila, so we must generate UUIDs. &#x20;

* **Photos schema (v0r1).**
  `photos` carries: `photo_uuid` (**NOT NULL**), `photo_id` (**NOT NULL, iNat photo id**), `observation_uuid` (**NOT NULL**), `license`, `width`, `height`, `position`, `origin`, `version`, `release`. Anthophila images **do not** have iNat `photo_id`, so `photo_id NOT NULL` is a hard blocker if we re‑use this table verbatim. &#x20;

* **Release/version/origin practice.**
  Ingestion tools set `origin`, `version`, `release` per table post‑load. We can use this to mark anthophila rows and to bump the dataset release to `r2`. &#x20;

* **Generator architecture.**
  The generator assembles **hybrid datasets** (images dir + HDF5 labels). The docs explicitly present an S3/Boto3 “downloader,” but the design is pluggable and the output is filesystem‑based; adding a **LocalFileProvider** is a natural extension. &#x20;

---

## High‑level design decisions

1. **Use a new data release `r2`** for any database that contains anthophila rows. This preserves **v0r1** as a pristine iNat‑only baseline and makes downstream exports/datasets reproducible by release tag. (We continue using `version='v0'`.)&#x20;

2. **Represent anthophila images as first‑class media** with minimal schema changes:

   * **Option A (recommended):** Create a new table `local_media` (or `media`) for non‑iNat assets, keyed by `asset_uuid`, with `observation_uuid`, `local_path`, `width`, `height`, `license`, `source_tag`, `sha256`, `phash`, `origin`, `version`, `release`. Keep `photos` reserved for iNat (with `photo_id NOT NULL`). This avoids loosening the iNat‑specific invariant on `photos`.
   * **Option B (fallback):** Allow `photos.photo_id` to be NULL and gate iNat code paths with `WHERE photo_id IS NOT NULL`. This reduces table sprawl but breaks the historical “photos == iNat photos” assumption.
     **Decision:** **Option A**, to preserve the iNat contract and avoid subtle regressions in duplicate checks that join on `photos.photo_id`. The duplicate‑probe snippet you have joins candidate IDs against `photos.photo_id` today, which assumes iNat semantics. Keeping that invariant intact is helpful.&#x20;

3. **Observation identifiers.** Generate **UUIDv4** for anthophila `observations.observation_uuid` (required) and store any parseable iNat IDs (observation or photo) as nullable *hints* on the media row (or in a sidecar `provenance` table) to assist duplicate logic and audit.

4. **Provenance & dedup.**

   * **Exact‑ID filter:** If filenames encode iNat Observation IDs (e.g., `..._10421352_1.jpg`), filter out any files whose observation ID is present in iNat tables. (But note: in your current dedup script the join is against `photos.photo_id`—which is a **photo id**, not an **observation id**—so we must correct this to avoid false negatives/positives.)&#x20;
   * **Image‑hash filter:** Compute `sha256` and a perceptual hash (e.g., pHash) for anthophila, and compare against a hashed index of iNat primaries to catch non‑ID duplicates (re‑uploads, re‑hosted copies). Add a small `media_hashes` table keyed by `asset_uuid`/`photo_uuid` to persist this.
   * **Within‑anthophila duplicates:** collapse by pHash/sha256; keep one “best” copy (largest resolution, or sharpest).

5. **Taxonomy mapping.** Parse the `genus_species` directory names, normalize (“\_” → space), and resolve to `taxon_id` with `typus` (exact name preferred; fall back to name‑only or synonym resolution). Enforce rank sanity: two tokens → L10 species, three → subspecies (L5), one token → genus (L20) unless `typus` says otherwise; raise for manual review on conflict. (This aligns with your rule of thumb.)

6. **Nulls & sentinels in `observations`.**

   * **Set**: `observation_uuid` (generated UUIDv4), `taxon_id` (via `typus`), `quality_grade='research'`, `origin='anthophila-expert-2025-08'`, `version='v0'`, `release='r2'`.
   * **NULL**: `observer_id`, `latitude`, `longitude`, `positional_accuracy`, `observed_on`, `anomaly_score`, `geom`, `elevation_meters`. (Docs and structure allow NULLs; `geom` can remain NULL if no lat/lon.) &#x20;

7. **Generator support for local images.**
   Add a **LocalFileProvider** to the downloader interface. If an image has only one available size, the preprocessor will center‑crop/resize with padding to the configured `IMG_SIZE`. This is fully consistent with the “hybrid” dataset target and the generator’s pipeline.&#x20;

---

## Milestones & acceptance criteria

### Milestone 0 — **Replay & harden the duplicate analysis (“fail fast”)**

**Why:** The current script joins anthophila IDs against `photos.photo_id`; if anthophila filenames encode **observation IDs**, this produces misleading counts. We must validate the “\~27k net‑new” claim with a corrected method.

**Work items (concise issues):**

1. **\[ibridaDB] anthophila filename parser & ID classifier**

   * Parse filenames → `{scientific_name, id_core, index_suffix, extension}`.
   * Heuristics to distinguish **iNat observation ids** vs **iNat photo ids** (e.g., try matching `id_core` to both domains in DB: `observations.observation_uuid/observation_id surrogate` *and* `photos.photo_id`; use counts to infer encoding).
   * **Accept.** Parser extracts name + one integer and classifies it as `maybe_observation_id | maybe_photo_id | unknown` with coverage stats over the corpus.

2. **\[ibridaDB] rigorous duplicate check (two‑pass)**

   * **Pass A (ID‑based)**:

     * If classified as **observation id**, check existence in **observations** via `observation_uuid` mapping table if you have one, else pivot to iNat export join (if an “observation id” integer is also present in your schema; if not, use a staging table to map obs IDs from exported CSV used to build the DB).
     * If classified as **photo id**, join to `photos.photo_id`.
   * **Pass B (image‑hash)**: pHash + sha256 probe against iNat primaries to catch non‑ID duplicates.
   * **Accept.** A CSV with `{filename, dup_reason: id|phash|sha256, matched_key}` and summary: duplicates %, new %, and confidence.

> **Note.** Your sample script that builds `temp_anthophila_ids(observation_id int)` and joins to `photos.photo_id` is a perfect skeleton; we’ll generalize it into the two‑pass logic above and add the image‑hash phase.&#x20;

---

### Milestone 1 — **Data normalization & staging**

**Work items:**

1. **\[ibridaDB/preprocess] scanner → `anthophila_manifest.csv`**

   * Output columns:
     `asset_uuid, original_path, flat_name, scientific_name_raw, scientific_name_norm, rank_guess, id_core, id_type_guess (obs|photo|unknown), width, height, sha256, phash, source_tag, license_guess, keep_flag`
   * **Accept.** 100% rows parse; sizes/hashes filled; `keep_flag` = false for known dups (from M0).

2. **\[typus] taxon resolver utility**

   * Resolve `scientific_name_norm` → `taxon_id`, plus `rank_level`, `rank`.
   * Flag invalid/mismatch; write `taxon_id` and `taxonomy_status` back to manifest.
   * **Accept.** ≥99% auto‑resolved; a JSON of leftovers for manual mapping.

3. **\[FS] flat directory materialization (`anthophila_flat/`)**

   * Copy or **hard‑link** kept images to a flat dir with canonical names:
     `asset_uuid.jpg` and a sidecar `asset_uuid.json` with provenance (`original_path`, `source_tag`, `sha256`, etc.).
   * **Accept.** `anthophila_flat/` exists; count matches `keep_flag==true`.

---

### Milestone 2 — **Database integration (r2)**

**Work items:**

1. **\[ibridaDB] `r2` release activation**

   * Run your existing “set version/origin/release en masse” script with `version='v0'`, `release='r2'`; set `origin='anthophila-expert-2025-08'` for the new rows. (This script already parallel‑updates `origin|version|release` by table.)&#x20;

2. **\[ibridaDB] schema for local media (no breakage to `photos`)**

   * Create `local_media` (or `media`) table:

     ```
     asset_uuid UUID PRIMARY KEY,
     observation_uuid UUID NOT NULL,
     local_path TEXT NOT NULL,
     width SMALLINT,
     height SMALLINT,
     license VARCHAR(255),
     source_tag VARCHAR(255),
     sha256 CHAR(64),
     phash  BIGINT,        -- or TEXT if you use hex
     inat_observation_id INTEGER NULL,
     inat_photo_id INTEGER NULL,
     origin VARCHAR(255),
     version VARCHAR(255),
     release VARCHAR(255)
     ```
   * Add unique index on `sha256` (optional: `phash` approximate search via LSH / extension later).
   * **Accept.** DDL applied; indices present; `photos` untouched.
     *(Rationale: preserve `photos.photo_id NOT NULL` contract.)*&#x20;

3. **\[ibridaDB] observations upsert**

   * Insert new rows into `observations` for kept anthophila assets:

     * `observation_uuid=uuid4()`, `taxon_id` from resolver, `quality_grade='research'`, `origin='anthophila-expert-2025-08'`, `version='v0'`, `release='r2'`; all geotemporal fields **NULL**.
   * **Accept.** Row counts match manifest; NOT NULL constraints honored (`observation_uuid` exists).&#x20;

4. **\[ibridaDB] local\_media insert**

   * One `local_media` row per kept image with `observation_uuid` FK.
   * **Accept.** FK validates; `local_path` points into `anthophila_flat/`.

5. **\[ibridaDB] provenance/validation queries**

   * Sanity checks: missing taxon IDs, duplicate sha256, orphaned media, wrong release/origin.
   * **Accept.** All checks pass or produce actionable diff reports.

---

### Milestone 3 — **ibrida.generator support for local files (single‑size)**

**Work items:**

1. **\[ibrida] Add `LocalFileProvider`**

   * New downloader impl that reads `local_media.local_path` rows instead of S3; no network I/O.
   * Interface‑compatible with existing downloader used in the pipeline diagram (source index → downloader → preprocessor → writer).&#x20;

2. **\[ibrida] Resolution negotiation**

   * If only one size exists, preprocessor center‑crops/resizes with padding to target `IMG_SIZE`. (The docs already describe the preprocessor stage doing resize/crop; we’re just applying it to a file path).&#x20;

3. **\[ibrida] Postgres/CSV source index for anthophila**

   * Extend the generator’s “input” layer to accept either a **Postgres query** (joining `observations` to `local_media`) or a manifest CSV bridging the two. The generator docs already anticipate `csv/sqlite/postgres` as inputs—lean on that.
   * **Accept.** A YAML config under `configs/generator/anthophila_*.yml` that builds a hybrid dataset from `local_media`.

4. **\[ibrida] Validation tests & docs**

   * `pytest` to cover LocalFileProvider, path resolution, and exact reproduction of `images/ + labels.h5` with anthophila rows.
   * Update `docs/modules/generator.md` with a “Local media” section & example config.&#x20;

---

### Milestone 4 — **Quality, licensing, and leakage controls**

**Work items:**

1. **\[ibridaDB] licensing sentinel policy**

   * For unknown licenses, set `license='unknown'` (or a controlled enum in `local_media`), and **tag** with `source_tag` (e.g., `xerces`, `licensed_dump`, `inat_export`).
   * Add filters in generator configs to **exclude** `license in ('unknown', ...)` when producing redistributable datasets.

2. **\[ibridaDB] train/val/test leakage guard**

   * Add a helper view or query to group by `sha256`/`phash` across `photos` and `local_media`, so generator can avoid splitting near‑duplicates across splits (or drop dupes relative to a “primary” source). (Optional now; highly recommended before large‑scale training.)

3. **\[ibrida] dataset QA report**

   * Emit per‑taxon counts, dimension histograms, and a random montage of K images per taxon to spot taxonomy mismaps and file issues.

---

### Milestone 5 — **Release r2 and export compatibility**

**Work items:**

1. **\[ibridaDB] Mark DB as `r2` and add release notes**

   * Document that `r2` == `r1` + anthophila local media + optional schema add (`local_media`).&#x20;
2. **\[ibridaDB] Export pipeline note**

   * If your current export jobs assume iNat‑only (`photos` join, elevation, geom, etc.), update docs to clarify that anthophila rows are **non‑spatial** and may be excluded by default unless `origin LIKE 'anthophila%'` is included. The export reference already treats geospatial features as optional; clarify that `geom`/`elevation_meters` can be NULL.&#x20;

---

## Proposed values for nulls & sentinels (observations + media)

* **observations**

  * `observation_uuid`: **uuid4()**
  * `taxon_id`: resolved by typus
  * `quality_grade`: `'research'`
  * `origin`: `'anthophila-expert-2025-08'`
  * `version`: `'v0'`
  * `release`: `'r2'`
  * `observer_id`, `latitude`, `longitude`, `positional_accuracy`, `observed_on`, `anomaly_score`, `geom`, `elevation_meters`: **NULL**
    *(All allowed by current structure/docs; `geom` present but nullable; `elevation_meters` optional.)* &#x20;

* **local\_media (new)**

  * `asset_uuid`: **uuid4()**
  * `observation_uuid`: FK to observations
  * `local_path`: absolute path in `anthophila_flat/`
  * `license`: `'unknown'` if unknown, else exact string
  * `source_tag`: `xerces|licensed_dump|inat_rehost|...`
  * `sha256`: computed
  * `phash`: computed
  * `inat_observation_id`, `inat_photo_id`: nullable **hints**
  * `origin`: `'anthophila-expert-2025-08'`
  * `version`: `'v0'`
  * `release`: `'r2'`

---

## Minimal DDL & indices (sketch)

```sql
-- 1) New table for non-iNat media
CREATE TABLE local_media (
  asset_uuid UUID PRIMARY KEY,
  observation_uuid UUID NOT NULL REFERENCES observations(observation_uuid),
  local_path TEXT NOT NULL,
  width SMALLINT,
  height SMALLINT,
  license VARCHAR(255),
  source_tag VARCHAR(255),
  sha256 CHAR(64),
  phash  TEXT,
  inat_observation_id INTEGER NULL,
  inat_photo_id INTEGER NULL,
  origin  VARCHAR(255),
  version VARCHAR(255),
  release VARCHAR(255)
);

CREATE UNIQUE INDEX local_media_sha256_uq ON local_media (sha256);
CREATE INDEX local_media_obs_uuid_ix ON local_media (observation_uuid);
CREATE INDEX local_media_origin_rel_ix ON local_media (origin, release);

-- 2) (Optional) Hash registry spanning iNat photos + local media (view)
CREATE VIEW unified_media_hashes AS
SELECT p.photo_uuid::text AS media_uuid, p.observation_uuid, NULL::text AS local_path, NULL::text AS sha256, NULL::text AS phash, 'photos' AS kind
FROM photos p
UNION ALL
SELECT asset_uuid::text, observation_uuid, local_path, sha256, phash, 'local_media'
FROM local_media;
```

*(We’re intentionally not altering `photos` so its `photo_id NOT NULL` remains a documented invariant for iNat assets.)*&#x20;

---

## Example ingest flow (scripts & responsibilities)

> Location: `ibridaDB/preprocess/anthophila/*` (replace stale contents as discussed)

1. **`00_scan_build_manifest.py`**

   * Walk `anthophila/` dir; parse scientific names; extract IDs from filenames; compute width/height, `sha256`, `phash`; write `anthophila_manifest.csv`.

2. **`01_typus_resolve_taxa.py`**

   * Read manifest; resolve `taxon_id` via typus; write back `taxon_id`, `rank_level`, `taxonomy_status`.

3. **`02_deduplicate.py`**

   * Load manifest; connect to DB;

     * Pass A: ID‑based check against iNat (`observations` or `photos` depending on id type).
     * Pass B: hash‑based check against iNat primaries.
   * Mark `keep_flag` accordingly + reason codes.

4. **`03_materialize_flat.py`**

   * Copy/hard‑link kept images into `anthophila_flat/`; write sidecar JSONs.

5. **`04_upsert_db.py`**

   * Insert `observations` rows (uuid4, null geotemporal, quality\_grade, origin/version/release).
   * Insert `local_media` rows with paths/hashes and iNat id hints.

6. **`05_verify.sql`**

   * Row counts, FK integrity, orphan scan, duplicate sha256 scan, origin/release correctness.

7. **`06_enable_r2.sh`**

   * Use the existing “set origin/version/release” script as needed for batch labeling across tables.&#x20;

---

## Generator integration (configs and usage)

* **Query source (Postgres).**
  Provide a small **materialized view** (or SQL) exposing anthophila rows:

  ```sql
  SELECT
    o.observation_uuid AS id,
    o.taxon_id,
    lm.local_path AS image_path,
    NULL::date as observed_on,
    NULL::double precision as latitude,
    NULL::double precision as longitude,
    NULL::double precision as elevation_meters,
    o.origin, o.release
  FROM observations o
  JOIN local_media lm USING (observation_uuid)
  WHERE o.origin LIKE 'anthophila-expert-%' AND o.release='r2';
  ```

* **Generator config (YAML sketch).**
  Extend your `configs/generator/*.yml` to include a Postgres block that reads from the view above, and set `output.mode: hybrid` (images/ + labels.h5). The docs already describe hybrid output, CSV/SQLite/Postgres sources, and validation checks to ensure `images/` paths exist. &#x20;

---

## Risks & mitigations

* **Wrong ID semantics in filenames.**
  *Risk:* joining anthophila IDs to `photos.photo_id` when the filename encodes an **observation id** yields incorrect duplicate rates.
  *Mitigation:* Milestone 0 parser + dual‑path joins (obs vs photo). Keep iNat contract on `photos` intact.&#x20;

* **Schema drift if we relax `photos.photo_id NOT NULL`.**
  *Risk:* existing tools assume photos == iNat.
  *Mitigation:* add `local_media`; leave `photos` untouched.&#x20;

* **License uncertainty.**
  *Risk:* non‑iNat sources may be restricted.
  *Mitigation:* default `license='unknown'`, add generator filters to exclude unknown/non‑permissive items for redistributable datasets.

* **Train/val leakage via cross‑source duplicates.**
  *Mitigation:* use `sha256`/`phash` groupings to keep near‑duplicates in the same split or drop duplicates.

---

## Acceptance checklist (end‑to‑end)

* [ ] Corrected duplicate audit shows <90% duplicates and aligns in magnitude with the agent’s estimate. (Report includes both ID‑based and hash‑based reasons.)
* [ ] `anthophila_manifest.csv` with `keep_flag` true for accepted items; `anthophila_flat/` populated; counts match.
* [ ] `observations` rows inserted with `origin='anthophila-expert-2025-08'`, `release='r2'`, null geotemporal fields. (NOT NULL constraints observed.)&#x20;
* [ ] `local_media` table exists; FK integrity clean; sha256 unique index has no collisions.
* [ ] ibrida.generator can build a hybrid dataset from anthophila rows via `LocalFileProvider`; produced `images/` and `labels.h5` pass validation checks documented in generator docs.&#x20;
* [ ] r2 release notes added to docs.

---

## Draft of concise issues to file (titles + one‑liners)

**ibridaDB (repo: ibridaDB)**

1. *Preprocess: parse anthophila filenames & build manifest (with ID type guess, hashes, sizes).*
2. *Preprocess: typus‑backed taxon resolver with rank sanity & error queue.*
3. *Preprocess: duplicate probe (obs‑id vs photo‑id checks + pHash/sha256 against iNat).*
4. *FS: materialize anthophila\_flat/ via copy or hard‑link; canonical naming; sidecar provenance.*
5. *DB: add `local_media` table; indices; FK to observations.*
6. *DB: upsert observations (uuid4, null geotemporal, research, origin/version/release).*
7. *DB: load local\_media rows; enforce sha256 uniqueness; optional “unified\_media\_hashes” view.*
8. *DB: verification SQL & counts; report generator.*
9. *Docs: r2 release notes & export caveats for non‑spatial rows.*

**ibrida (repo: ibrida)**
10\. *generator: add LocalFileProvider (filesystem loader) parallel to S3 downloader.*
11\. *generator: single‑size support (resize/pad to IMG\_SIZE) + tests.*
12\. *generator: Postgres/CSV config example for anthophila; validation harness.*
13\. *generator: leakage guard hooks (optional now): avoid split crossing by sha256 group.*
14\. *docs: update `docs/modules/generator.md` with “Local media” and example config.*&#x20;

---

## Open questions (answer whenever convenient)

1. **Table name preference:** `local_media` vs `media`. (I’ve used `local_media` to be explicit.)
`media` is appealing because I anticipate bringing other internal, non-iNat datasets into ibridaDB in the future... and these might not be local files; they might instead be on a bucket (I have private backblaze b2 buckets that I use for storing some datasets, in the long-run I anticipate migrating more local-only data to those bucekts as funds become available). In this context, are the functional differneces of local media vs. media sufficient to justify semantic separation? Assume that (as you mention) `photos` is reserved for iNat assets (it is essentially a copy of the `photos` table that iNaturalist exports monthly). I like your suggestion that we should use `release` `r2` for these data; reserving `r1` for the existing iNat-only data (generated from December 2024 iNat export). our `r2` dataset release will include both iNat and anthophila data (I might pull the latest iNat export, Aug2025, and we generate `r2` with both iNat and anthophila data, instead of just copying the existing r1 data which at this point is missing ~9months of observations).
2. **License policy:** OK to set `license='unknown'` and hard‑exclude unknown for public/reproducible datasets?
Yes, license is unknown for anthophila data. We will have to exclude these from any public datasets, although I don't anticipate releasing any public datasets in the near (or even medium) term. I'm a startup, not an acedemic, so I release open weights but I don't open-source the full pipeline.
3. **Negative synthetic IDs vs new table:** If you prefer no new table, we can relax `photos.photo_id` to nullable and reserve **negative** IDs for local assets—but that abandons the “photos == iNat” invariant.
4. **Provenance depth:** Do we want a separate `provenance` table (richer metadata, parsing notes, original filename, etc.), or are `local_media.source_tag` and sidecars sufficient?
I think source tag and sidecars are sufficient for now. I simply don't have much information about the source of the `anthophila` data. However, we might revisit this question later when I produce machine-enhanced trainin data with ibrida.distill (e.g. cropping training images to the specimen of interest; adding annotations to the images.. we'll want to track provenance/processing steps there, but that's a different question and I am not ready to answer it yet).
5. **Hashing standard:** `sha256 + pHash` acceptable, or do you prefer `dHash/aHash` variants too?
I don't have a preference.
6. **Release tag:** Using `release='r2'` to mean “r1 + anthophila”. Good?
Eh, I think this is a good opportunity to pull fresh iNat data. There was actually a fresh release yesterday: `iNatOpenData:inaturalist-open-data/metadata/inaturalist-open-data-20250827.tar.gz`, so that's 9 months of iNat data that we're missing (and northern hemisphere summer data is espec valuable-- a lot of good pollinators in there).
This is a bit more involved, insofar as we'll need to regenerate our tables. I think we have it current set up so that the database itself is versioned? So our db name is `ibrida-v0` (tbh not sure if that was a good idea or not.. if you think not, then this is a good chance to course-correct and *not* spin up separate database for each release-- let me know your thoughts). We have a fairly robust family of scripts for ingesting data, so there's not a lot of technical complexity here, just additional runtime reqs.. the only think I'm concerned about is how long it takes to add the DEM data and calculate elevation_meters for all the observations. I recall that taking literally *weeks* to process. 
Given this, I wonder if it's a better idea to maybe rename the `ibrida-v0` database to `ibrida-v0` and have our v0 releases on the same database. And then instead of ingesting *all* iNat observations ever made into a fresh db, we can just get the observations (and corresponding photos rows) from the latest Aug2025 iNat export whose `observations.observed_on` is after the last iNat export we ingested (i.e. Dec2024). I believe that r1/Dec2024 had a cutoff date of 20241127 (YYYYMMDD format). So we can get the observations from between Dec2024 and Aug2025. Of course there's some subtleties here and so I welcome your thoughts on how best to approach this. It's been a while since I tried to do this but I remember there being some complications, e.g. I am not sure that we always have a primary key on the inat tables (observations, photos, observers, taxa) that we can use to trivially merge new data into the existing tables, which is why I am suggesting the date range approach.. for the photos tables, I think we can use the set of observation_uuid values that are new in the r2 release (and that we are adding to `observations`) to get the photos rows that we need to add to our existing `photos` table. For `observers`, maybe we can look at the 'last' observer_id value in the existing `observers` table and start there? Might be a more robust way to do this, espec if we have any reason to believe the row order of observers isn't idempotent. Actually, I think `observers.observer_id` is int, ascending, so we can just get the highest observer_id value from existing observers table and start there (add any row from r2/Aug2025 observers table whose observer_id higher than this). I prefer to not just replace the existing Dec2024/v1 tables with the new ones because I don't want to lose any rows that are not in the new dataset (e.g. users sometimes delete accounts, photos.. but I don't want to lose my records of these, so I want to add new stuff, not replace tables wholesale).
Taxa is subtle. I am crossing my fingers that there are no breaking changes in taxon_id b/w Dec2024 and Aug2025. I expect that there's probably a few changes to the taxonomy, but they'll be for obscure/archaic taxon which do not impact any of our observations. But we must do a pre-flight check here and compare the Dec2024 taxa table against the Aug2025 taxa table; if we have >1 observation that will be affected by changes in taxonomy then we will have to pause and devise a mapping plan *before* adding new observations. We *shouldn't* have any problems here, but we must be aware of any relevant taxonomy revisions as carelessness here can cause blow-ups downstream. We can load in a temp Aug2025 (r2) taxa table; please devise an ironclad analysis plan to determine existence or nonexistence of breaking changes b/w the two tables.. limit scope to these cols:
```
| Column     | Type              | Description |
|------------|-------------------|-------------|
| taxon_id   | integer           | Unique taxon identifier. |
| ancestry   | varchar(255)      | Encoded ancestral hierarchy (delimited by backslashes). |
| rank_level | double precision  | Numeric level indicating taxonomic rank. |
| rank       | varchar(255)      | Taxonomic rank (e.g., "species", "genus"). |
| name       | varchar(255)      | Scientific name of the taxon. |
| active     | boolean           | Indicates if the taxon is active in the taxonomy. |
```
The existing `taxa` table also has `origin`, `version`, `release` columns; these can be ignored for the purposes of this analysis.
I have some existing scripts and such for this flavor of analysis in `/home/caleb/repo/ibridaDB/dbTools/taxa`, however I haven't used these in perhaps a year or more so I am not sure of their status.. provide tickets to revise or re-draft these scripts as-needed (be explicit with reqs).

If there's no breaking changes (i.e. none of the new r2 observations we're adding have a taxon_id that is affected by a change in taxonomy), then there's no need to regenerate taxa (nor expanded_taxa). If there *are* breaking changes.. we'll have to regenerate taxa and expanded_taxa (the latter with `dbTools/taxa/expand/expand_taxa.sh`, then add the immediate ancestor columns with a re-run of `scripts/add_immediate_ancestors.py`)... and then remap the affected observations to the new taxa. Hopefully we do not need to do this, but we have to verify that we have no observations that are affected by a change in taxonomy. So you should devise a plan + instructions for the AI to perform this analysis; please be explicit with reqs.

I have already pulled the Aug2025 `r2` CSVs from the iNatOpenData bucket to our local box:
```bash
caleb@blade:/datasets/ibrida-data/intake/Aug2025$ ls
observations.csv  observations_projects.csv  observers.csv  photos.csv  projects.csv  taxa.csv
```
Looks like there's new tables, projects and observations_projects..  we don't need those, let's just ignore them and focus on our four core tables.

---

## Appendix: quick schema & doc references (internal)

* `observations` / `photos` structure (v0r1); `observation_uuid` and `photo_id` are NOT NULL in structure.sql; `origin/version/release` are added by ingestion; `geom` present.&#x20;
* Canonical schema reference & column descriptions (incl. `elevation_meters` optional).&#x20;
* Ingestion script pattern that bulk‑sets `origin/version/release`.&#x20;
* Release notes (v0r1 now; r2 is our proposed next).&#x20;
* Generator architecture and hybrid dataset docs. &#x20;
* Current duplicate probe skeleton joining temp IDs to `photos.photo_id` (to refine).&#x20;

---

If you’d like, I can turn the items above into fully‑formatted GitHub issues next, including checklists, acceptance criteria, and stubbed SQL/Python snippets per task.
