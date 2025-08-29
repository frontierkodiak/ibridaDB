Perfect—thanks for the detailed notes. Below is a concrete, end‑to‑end plan you can hand to the AI/ETL, including DDL, staging/ingest steps, the “ironclad” taxonomy‑diff preflight, and the small set of script tickets to (re)enable automation.

---

## A. Decisions (locked)

1. **Table name:** use **`media`** (generic), keep **`photos`** strictly iNat.

   * Rationale: future assets may live on B2/S3/HTTP as well as local disk; a single `media` table with a `uri` handles all. The invariant “`photos` == iNat” remains intact.

2. **License policy:** set `license='unknown'` for anthophila; **exclude unknown** from any public/reproducible views. (See §C.3 for views.)

3. **IDs:** **Do not** use negative synthetic IDs in `photos`. Keep `photos.photo_id` as the iNat primary key; place all non‑iNat assets in `media`.

4. **Provenance:** For now, **`source_tag` + `sidecar` JSONB** on `media` is sufficient.

5. **Hashing:** **`sha256` + 64‑bit pHash** as first‑class. (Room for `ahash`, `dhash` nullable columns later.)

6. **Release tag:** Use **`release='r2'`** to denote “Dec‑2024 iNat (r1) + Aug‑2025 iNat delta + anthophila media”. We’ll **incrementally import** Aug‑2025 iNat instead of rebuilding from scratch.

---

## B. Minimal schema changes

### B.1 Create generic `media` + junction

```sql
-- 1) Generic media catalog covering local files, B2, S3, HTTP, etc.
create table if not exists media (
  media_id           bigserial primary key,
  dataset            text not null,              -- e.g. 'anthophila', 'inat-mirror', etc.
  release            text not null,              -- e.g. 'r2'
  source_tag         text not null,              -- short provenance tag (e.g. 'anthophila-2025-08')
  uri                text not null,              -- e.g. file:///..., b2://bucket/key, s3://..., https://...
  uri_scheme         text generated always as (
                       split_part(uri, '://', 1)
                     ) stored,
  sha256_hex         text,                       -- lowercase hex; nullable until computed
  phash_64           bigint,                     -- perceptual hash
  width_px           integer,
  height_px          integer,
  duration_ms        integer,                    -- for audio/video
  mime_type          text,
  file_bytes         bigint,
  captured_at        timestamptz,
  sidecar            jsonb default '{}'::jsonb,  -- arbitrary metadata/notes
  license            text not null default 'unknown',
  created_at         timestamptz not null default now(),
  unique (uri),
  unique (sha256_hex)
);

-- 2) Optional: link media to observations (works for iNat obs and any future obs-like rows)
create table if not exists observation_media (
  observation_uuid   uuid not null,
  media_id           bigint not null references media(media_id) on delete cascade,
  role               text not null default 'primary',  -- 'primary' | 'derived' | 'crop' | ...
  added_at           timestamptz not null default now(),
  primary key (observation_uuid, media_id)
);
create index if not exists observation_media_obs_idx on observation_media(observation_uuid);
create index if not exists observation_media_media_idx on observation_media(media_id);
```

> **Note:** We’re not attaching anthophila assets to iNat observations, so you can load anthophila into `media` now and wire up junctions later if needed.

### B.2 Ensure iNat core tables have proper keys (idempotent)

If not already present, lock these in:

```sql
alter table if exists observations
  add primary key (observation_uuid);
alter table if exists photos
  add primary key (photo_id);
alter table if exists observers
  add primary key (observer_id);
alter table if exists taxa
  add primary key (taxon_id);
```

(If PKs already exist, these `alter`s will no‑op/fail harmlessly; adjust with `if not exists` per your PG version.)

### B.3 Public views (licenses)

```sql
create or replace view public_observations as
select *
from observations
where coalesce(license, 'unknown') not in ('unknown', 'restricted');

create or replace view public_media as
select *
from media
where coalesce(license, 'unknown') not in ('unknown', 'restricted');
```

---

## C. Database naming and tracking

### C.1 Rename DB once to drop the `-r1` suffix

From a different database:

```sql
-- connect to 'postgres' or any db other than the target first
-- then:
alter database "ibrida-v0" rename to "ibrida-v0";
```

Update your env/config to point to `ibrida-v0`.

### C.2 Track releases and sources centrally

```sql
create table if not exists releases (
  release           text primary key,   -- e.g. 'r1', 'r2'
  imported_at       timestamptz not null default now(),
  source_notes      text,               -- free text (e.g. iNat 2024-11-27 + anthophila set)
  cutoff_observed_on date,              -- for iNat imports
  inat_export_tag   text                -- e.g. '20250827'
);
```

Insert rows for `r1` (backfill) and `r2` (when you start).

---

## D. r2 incremental iNat import (Aug‑2025)

**Goal**: add only *new* iNat rows (obs/photos/observers/taxa‑new) since r1’s cutoff (you wrote: **2024‑11‑27**). We’ll use a staging schema and idempotent upserts.

### D.1 Create staging schema and load CSVs

```sql
create schema if not exists stg_inat_20250827;

drop table if exists stg_inat_20250827.observations;
drop table if exists stg_inat_20250827.photos;
drop table if exists stg_inat_20250827.observers;
drop table if exists stg_inat_20250827.taxa;

create table stg_inat_20250827.observations (like observations including all);
create table stg_inat_20250827.photos       (like photos including all);
create table stg_inat_20250827.observers    (like observers including all);
create table stg_inat_20250827.taxa         (like taxa including all);

-- Load from local CSVs (run in psql client on blade)
\copy stg_inat_20250827.observations from '/datasets/ibrida-data/intake/Aug2025/observations.csv' csv header;
\copy stg_inat_20250827.photos       from '/datasets/ibrida-data/intake/Aug2025/photos.csv'       csv header;
\copy stg_inat_20250827.observers    from '/datasets/ibrida-data/intake/Aug2025/observers.csv'    csv header;
\copy stg_inat_20250827.taxa         from '/datasets/ibrida-data/intake/Aug2025/taxa.csv'         csv header;

analyze stg_inat_20250827.observations;
analyze stg_inat_20250827.photos;
analyze stg_inat_20250827.observers;
analyze stg_inat_20250827.taxa;
```

*(If `like … including all` fails on your current table options, create explicit columns or `LIKE … INCLUDING DEFAULTS`.)*

### D.2 Determine the actual r1 cutoff (safety check)

Even though you believe it’s `2024‑11‑27`, confirm:

```sql
select max(observed_on) as last_r1_observed_on
from observations
where origin = 'inat' and release = 'r1';
```

Let `:cutoff_date` be that result (expected `2024‑11‑27`). We’ll filter strictly **`observed_on > :cutoff_date`**. (If `observed_on` can be null, nulls will be excluded—matching your intent.)

### D.3 Precompute the r2 *new observation* set in staging

```sql
-- Observations strictly after the cutoff date
create temp table stg_new_obs_uuid as
select o.observation_uuid
from stg_inat_20250827.observations o
where o.observed_on > date :cutoff_date;
create index on stg_new_obs_uuid(observation_uuid);
```

### D.4 **Taxonomy preflight (ironclad)** — see Section E for the full runbook

This step **must** pass before any rows are inserted:

* Every `taxon_id` referenced by `stg_new_obs_uuid` that already exists in `taxa` **must not** have *breaking* diffs between r1 and r2 (`ancestry`, `rank_level`, `rank` changed) and should ideally not flip `active` from true→false. Name‑only changes are **non‑breaking**.

If **any breaking diffs** are found, **abort the ingest**, produce the report CSVs, and decide whether to (a) regenerate `taxa` + `expanded_taxa` then remap, or (b) temporarily skip only observations that reference the breaking `taxon_id`s.

### D.5 Insert new iNat rows

**Observations** (idempotent upsert; we don’t mutate r1):

```sql
insert into observations (
  -- list your columns explicitly; example below
  observation_uuid, /* … other cols … */ origin, release, version
)
select
  o.observation_uuid, /* … other cols … */ 'inat' as origin, 'r2' as release, '20250827' as version
from stg_inat_20250827.observations o
join stg_new_obs_uuid n using (observation_uuid)
on conflict (observation_uuid) do nothing;
```

**Photos** (only those tied to the new observations):

```sql
insert into photos (
  photo_id, /* … other cols … */ origin, release, version
)
select
  p.photo_id, /* … other cols … */ 'inat', 'r2', '20250827'
from stg_inat_20250827.photos p
join stg_inat_20250827.observations o using (observation_uuid)
join stg_new_obs_uuid n on n.observation_uuid = o.observation_uuid
on conflict (photo_id) do nothing;
```

**Observers** (true set‑based merge; more robust than “> max(id)”):

```sql
insert into observers as tgt (
  observer_id, /* … other cols … */ origin, release, version
)
select
  s.observer_id, /* … other cols … */ 'inat', 'r2', '20250827'
from stg_inat_20250827.observers s
left join observers tgt using (observer_id)
where tgt.observer_id is null;
```

**Taxa (new ones only)**:

```sql
insert into taxa as tgt (
  taxon_id, ancestry, rank_level, rank, name, active,
  origin, release, version
)
select
  s.taxon_id, s.ancestry, s.rank_level, s.rank, s.name, s.active,
  'inat', 'r2', '20250827'
from stg_inat_20250827.taxa s
left join taxa tgt using (taxon_id)
where tgt.taxon_id is null;
```

*(If the preflight found zero breakers, we do **not** update existing taxa rows. If you want name‑only refreshes, add a narrow `on conflict do update set name=excluded.name` with a `where tgt.name is distinct from excluded.name`.)*

### D.6 Elevation (DEM) only for the r2 delta

Create a working set and process just those:

```sql
create temp table stg_r2_obs_for_elev as
select o.*
from observations o
where o.release = 'r2' and o.origin = 'inat'
  and o.elevation_meters is null
  and o.latitude is not null and o.longitude is not null;
```

Then point your existing elevation pipeline at `stg_r2_obs_for_elev`. (Ticket below proposes a cached, tile‑based approach to keep it incremental by default.)

---

## E. **Ironclad taxonomy‑diff preflight** (r1 vs r2)

**Scope:** Compare **only** the `taxon_id`s referenced by **new r2 observations** (the set in `stg_new_obs_uuid`). Columns considered:

* `taxon_id` (key), `ancestry` (string of ancestor ids delimited by `\`), `rank_level` (double), `rank` (text), `name` (text), `active` (bool).
* Existing `taxa.origin/version/release` are ignored for this check.

### E.1 Build comparison tables

```sql
-- r2 taxa restricted to the new obs set
create temp table stg_r2_taxa_needed as
select distinct t.*
from stg_inat_20250827.taxa t
join stg_inat_20250827.observations o using (taxon_id)
join stg_new_obs_uuid n on n.observation_uuid = o.observation_uuid;

-- slice of current (r1+) taxa that intersect that set
create temp table curr_taxa_slice as
select t.*
from taxa t
join (select distinct taxon_id from stg_r2_taxa_needed) x using (taxon_id);
```

### E.2 Diff and classify

```sql
-- union‑all two sources to make comparison easier
create temp view _cmp as
select 'r1' as src, c.taxon_id, c.ancestry, c.rank_level, c.rank, c.name, c.active
from curr_taxa_slice c
union all
select 'r2' as src, n.taxon_id, n.ancestry, n.rank_level, n.rank, n.name, n.active
from stg_r2_taxa_needed n;

-- pivot into one row per taxon_id with old/new
create temp table taxa_cmp as
select
  t.taxon_id,
  max(case when src='r1' then ancestry   end) as ancestry_r1,
  max(case when src='r2' then ancestry   end) as ancestry_r2,
  max(case when src='r1' then rank_level end) as rank_level_r1,
  max(case when src='r2' then rank_level end) as rank_level_r2,
  max(case when src='r1' then rank       end) as rank_r1,
  max(case when src='r2' then rank       end) as rank_r2,
  max(case when src='r1' then name       end) as name_r1,
  max(case when src='r2' then name       end) as name_r2,
  max(case when src='r1' then active     end) as active_r1,
  max(case when src='r2' then active     end) as active_r2
from _cmp t
group by t.taxon_id;

-- classify differences
create temp table taxa_diffs as
select
  *,
  (ancestry_r1 is distinct from ancestry_r2)   as ancestry_changed,
  (rank_level_r1 is distinct from rank_level_r2) as rank_level_changed,
  (rank_r1 is distinct from rank_r2)           as rank_changed,
  (name_r1 is distinct from name_r2)           as name_changed,
  (active_r1 is distinct from active_r2)       as active_changed,
  case
    when ancestry_r1 is distinct from ancestry_r2 then 'BREAKING: ancestry'
    when rank_level_r1 is distinct from rank_level_r2 then 'BREAKING: rank_level'
    when rank_r1 is distinct from rank_r2 then 'BREAKING: rank'
    when active_r1 = true and active_r2 = false then 'BREAKING: deactivated'
    when active_r1 = false and active_r2 = true then 'nonbreaking: reactivated'
    when name_r1 is distinct from name_r2 then 'nonbreaking: name'
    else 'nochange'
  end as diff_class
from taxa_cmp;
```

### E.3 Report and gate

```sql
-- counts by class
select diff_class, count(*) from taxa_diffs group by 1 order by 1;

-- the set that will BLOCK the import
select taxon_id, ancestry_r1, ancestry_r2, rank_level_r1, rank_level_r2, rank_r1, rank_r2, active_r1, active_r2
from taxa_diffs
where diff_class like 'BREAKING%';

-- optionally, the "name only" diffs
select taxon_id, name_r1, name_r2
from taxa_diffs
where diff_class = 'nonbreaking: name';
```

**Gate rule:** proceed only if **no rows** in `diff_class like 'BREAKING%'`.
If non‑zero, export two CSVs for triage:

```sql
\copy (
  select * from taxa_diffs where diff_class like 'BREAKING%'
) to '/tmp/r2_taxa_breaking.csv' csv header;

\copy (
  select * from taxa_diffs where diff_class = 'nonbreaking: name'
) to '/tmp/r2_taxa_nameonly.csv' csv header;
```

*Mapping deactivations/splits/merges is outside the four‑table scope; that’s why we fail fast here. If needed later, we can ingest iNat taxon change logs to programmatically remap.*

---

## F. Anthophila media ingest (into `media`)

A minimal, parallel pipeline:

1. Compute `sha256_hex`, `phash_64`, basic metadata (height/width/mime/bytes) for each file.
2. Insert into `media` with `dataset='anthophila'`, `release='r2'`, `source_tag='anthophila-2025-08'`, `license='unknown'`, and a `file://` URI (or `b2://` if already uploaded).
3. (Optional) record any annotations in `sidecar` JSONB for now.

Example insert (batch via `COPY` or parameterized INSERTs):

```sql
insert into media (dataset, release, source_tag, uri, sha256_hex, phash_64,
                   width_px, height_px, mime_type, file_bytes, captured_at, license, sidecar)
values
('anthophila','r2','anthophila-2025-08','file:///datasets/anthophila/img001.jpg',
 '…sha256…', 1234567890123456789, 2048, 1365, 'image/jpeg', 3456789, null, 'unknown',
 '{"note":"raw import"}'::jsonb)
on conflict (uri) do nothing;
```

---

## G. Elevation pipeline (incrementalization)

**Design tweak:** Drive elevation by a *work queue* view.

```sql
create or replace view elevation_todo as
select observation_uuid, latitude, longitude
from observations
where origin='inat' and release='r2'
  and elevation_meters is null
  and latitude is not null and longitude is not null;
```

Then modify your elevation job to repeatedly `select … for update skip locked` from `elevation_todo`, compute, `update observations set elevation_meters=… where observation_uuid=…`.
**Optional optimization:** cache by S2 cell or geohash to cut repeat DEM reads; implement a small table:

```sql
create table if not exists elev_cache (
  geohash7 text primary key,
  elevation_meters real,
  samples integer default 0,
  updated_at timestamptz default now()
);
```

---

## H. Tickets (explicit, actionable)

> Paths assume repo root at `/home/caleb/repo/ibridaDB/`.

### H1 — **Add `media` + `observation_media` DDL & migrations**

* **Files:** `db/migrations/2025-08-28_media.sql`
* **Tasks:**

  * Add DDL from §B.1.
  * Add `public_media` view from §B.3.
  * Flyway/psql migration tested idempotently.
* **Acceptance:** `select count(*) from information_schema.tables where table_name in ('media','observation_media');` returns 2; `public_media` view exists.

### H2 — **Ensure PKs on core iNat tables**

* **Files:** `db/migrations/2025-08-28_pk_guards.sql`
* **Tasks:** Add the `alter table … add primary key` guards (or create unique indexes + attach PK if missing).
* **Acceptance:** `pg_indexes` shows unique/PK on `(observation_uuid)`, `(photo_id)`, `(observer_id)`, `(taxon_id)`.

### H3 — **Staging loader for Aug‑2025 export**

* **Files:** `dbTools/inat/load_staging_20250827.sh`, `dbTools/inat/stg_tables_20250827.sql`
* **Tasks:**

  * Create `stg_inat_20250827` schema + LIKE tables.
  * `\copy` CSVs from `/datasets/ibrida-data/intake/Aug2025/`.
  * Run `analyze`.
* **Acceptance:** Row counts in staging match CSV line counts minus header.

### H4 — **Taxonomy preflight (SQL first‑class)**

* **Files:** `dbTools/taxa/check_breakers.sql`
* **Tasks:**

  * Emit the SQL from §E (E.1–E.3) parameterized by `:cutoff_date` and staging schema name.
  * Write two CSVs if breakers or name‑only diffs exist.
  * Exit non‑zero (shell) if breakers > 0.
* **Acceptance:** On a dry run, `diff_class` summary prints; script exits non‑zero when breakers present.

### H5 — **ETL: delta import (observations/photos/observers/taxa‑new)**

* **Files:** `dbTools/inat/import_delta_20250827.sql`
* **Tasks:**

  * Use SQL in §D.5 for idempotent inserts.
  * Tag rows with `origin='inat'`, `release='r2'`, `version='20250827'`.
* **Acceptance:** Counts of inserted rows equal counts from the staging filters; rerunning is a no‑op.

### H6 — **Anthophila → `media` import**

* **Files:** `dbTools/media/anthophila_ingest.py`
* **Tasks:**

  * Walk the anthophila directory; compute `sha256` and pHash; gather metadata.
  * Batch‑insert into `media` (`dataset='anthophila'`, `release='r2'`, `source_tag='anthophila-2025-08'`, `license='unknown'`).
* **Acceptance:** Number of `media` rows equals file count; re‑runs skip existing (`on conflict (uri) do nothing`); verify `unique (sha256_hex)` constraint is respected.

### H7 — **Elevation: incremental work‑queue + cache**

* **Files:** `dbTools/elevation/fill_r2_elev.py`, `db/migrations/2025-08-28_elev_cache.sql`
* **Tasks:**

  * Create `elevation_todo` view and optional `elev_cache` table (§G).
  * Modify job to process only `elevation_todo`.
  * Add simple geohash‑7 cache to avoid redundant DEM hits.
* **Acceptance:** After running, `select count(*) from elevation_todo;` steadily decreases to zero, with spot‑checked elevations populated.

### H8 — **Taxa expansion (only if preflight fails)**

* **Files:** `dbTools/taxa/expand/expand_taxa.sh`, `scripts/add_immediate_ancestors.py`
* **Tasks (gated):**

  * If breakers exist, regenerate `taxa` and `expanded_taxa` from r2 staging.
  * Re‑run `add_immediate_ancestors.py` to rebuild ancestor columns.
  * Prepare a targeted remap script for affected `observation_uuid`s.
* **Acceptance:** `expanded_taxa` row count and parent columns are consistent; affected observations re‑point to new `taxon_id`s per your mapping decision.

---

## I. “AI runbook” (what the automation should literally do)

1. **Set variables**

   * `DB=ibrida-v0`
   * `STG_SCHEMA=stg_inat_20250827`
   * `CUTOFF=$(psql … -t -A -c "select max(observed_on)::text from observations where origin='inat' and release='r1';")`
     *(Expect `2024-11-27`.)*

2. **Create staging schema & load CSVs** using §D.1.

3. **Compute `stg_new_obs_uuid`** using §D.3 (with `$CUTOFF`).

4. **Run taxonomy preflight** by executing `dbTools/taxa/check_breakers.sql`.

   * If any `diff_class like 'BREAKING%'`, **stop**, save `/tmp/r2_taxa_breaking.csv`, and exit non‑zero.
   * If only `name` diffs, continue.

5. **Insert delta** in this order:

   * `observations` (r2 delta)
   * `photos` (join to the new obs set)
   * `observers` (left‑join anti‑merge)
   * `taxa` (new IDs only)

6. **Record release**:

   ```sql
   insert into releases (release, source_notes, cutoff_observed_on, inat_export_tag)
   values ('r2', 'Aug-2025 iNat delta + anthophila media', date $CUTOFF, '20250827')
   on conflict (release) do nothing;
   ```

7. **Kick elevation worker** (pointed at `elevation_todo`).

8. **Anthophila ingest** into `media` with hashing & metadata; verify via `select count(*) from media where dataset='anthophila' and release='r2';`.

9. **Sanity checks**

   * New obs count: `select count(*) from observations where release='r2' and origin='inat';`
   * Photos tied to r2 obs: spot join count.
   * Zero breakers in `/tmp/r2_taxa_breaking.csv` (if file exists, fail).

---

## J. A few guard‑rail indices (optional but helpful)

```sql
create index if not exists observations_release_idx on observations(release) where origin='inat';
create index if not exists photos_obs_idx on photos(observation_uuid);
create index if not exists taxa_rank_idx on taxa(rank, active);
create index if not exists media_dataset_release_idx on media(dataset, release);
```

---

## K. Notes on subtle points

* **Date filter:** We’re using **`observed_on > cutoff`** as you prefer. (No timezones to worry about; `observed_on` is a date.)
* **Deletions upstream:** We intentionally **do not delete** local rows when iNat removes users/photos; your historical retention requirement remains satisfied.
* **Name‑only changes:** Taxon `name` changes with identical `rank/rank_level/ancestry` are treated as non‑breaking; you may opt to refresh names later if desired.
* **Projects tables:** Ignored, as requested.

---

If you’d like, I can collapse the SQL from sections D & E into two ready‑to‑run scripts (`import_delta_20250827.sql` and `check_breakers.sql`) matching your repo layout in the tickets above.
