-- IBRIDA-009: Import r2 delta from staging (idempotent)
\timing on
\set ON_ERROR_STOP on

\if :{?stg_schema}
\else
\set stg_schema 'stg_inat_20250827'
\endif
\if :{?origin}
\else
\set origin 'inat'
\endif
\if :{?version}
\else
\set version '20250827'
\endif
\if :{?release}
\else
\set release 'r2'
\endif

\echo 'Using staging schema :' :stg_schema
\echo 'Origin/Version/Release:' :origin :version :release

-- Ensure origin/version/release columns exist (no-op if already present)
ALTER TABLE observations ADD COLUMN IF NOT EXISTS origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN IF NOT EXISTS version VARCHAR(255);
ALTER TABLE observations ADD COLUMN IF NOT EXISTS release VARCHAR(255);
ALTER TABLE photos ADD COLUMN IF NOT EXISTS origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN IF NOT EXISTS version VARCHAR(255);
ALTER TABLE photos ADD COLUMN IF NOT EXISTS release VARCHAR(255);
ALTER TABLE observers ADD COLUMN IF NOT EXISTS origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN IF NOT EXISTS version VARCHAR(255);
ALTER TABLE observers ADD COLUMN IF NOT EXISTS release VARCHAR(255);
ALTER TABLE taxa ADD COLUMN IF NOT EXISTS origin VARCHAR(255);
ALTER TABLE taxa ADD COLUMN IF NOT EXISTS version VARCHAR(255);
ALTER TABLE taxa ADD COLUMN IF NOT EXISTS release VARCHAR(255);

-- Index staging tables for faster joins (safe if already exists)
CREATE INDEX IF NOT EXISTS idx_stg_obs_uuid ON :stg_schema.observations (observation_uuid);
CREATE INDEX IF NOT EXISTS idx_stg_obs_taxon ON :stg_schema.observations (taxon_id);
CREATE INDEX IF NOT EXISTS idx_stg_photos_obs_uuid ON :stg_schema.photos (observation_uuid);
CREATE INDEX IF NOT EXISTS idx_stg_photos_photo_id ON :stg_schema.photos (photo_id);
CREATE INDEX IF NOT EXISTS idx_stg_observers_id ON :stg_schema.observers (observer_id);
CREATE INDEX IF NOT EXISTS idx_stg_taxa_id ON :stg_schema.taxa (taxon_id);

ANALYZE :stg_schema.observations;
ANALYZE :stg_schema.photos;
ANALYZE :stg_schema.observers;
ANALYZE :stg_schema.taxa;

-- Determine cutoff date from existing observations
\echo 'Finding cutoff date...'
CREATE TEMP TABLE r1_cutoff AS
SELECT MAX(observed_on) as max_date FROM observations;

\echo 'Cutoff date:'
SELECT * FROM r1_cutoff;

-- Identify new observations (strictly after cutoff or not present)
\echo 'Identifying new observations...'
CREATE TEMP TABLE r2_new_obs AS
SELECT DISTINCT o.observation_uuid, o.taxon_id
FROM :stg_schema.observations o
WHERE o.observed_on > (SELECT max_date FROM r1_cutoff)
   OR NOT EXISTS (SELECT 1 FROM observations r1 WHERE r1.observation_uuid = o.observation_uuid);

CREATE INDEX idx_r2_new_obs_uuid ON r2_new_obs(observation_uuid);

\echo 'New observations count:'
SELECT COUNT(*) FROM r2_new_obs;

-- Insert taxa first (for FK integrity)
\echo 'Inserting new taxa...'
INSERT INTO taxa (taxon_id, ancestry, rank_level, rank, name, active, origin, version, release)
SELECT t.taxon_id, t.ancestry, t.rank_level, t.rank, t.name, t.active, :origin, :version, :release
FROM :stg_schema.taxa t
WHERE t.taxon_id IN (SELECT taxon_id FROM r2_new_obs)
  AND NOT EXISTS (SELECT 1 FROM taxa existing WHERE existing.taxon_id = t.taxon_id);

\echo 'Inserted taxa:'
SELECT COUNT(*) FROM taxa WHERE release = :release AND origin = :origin;

-- Insert observations
\echo 'Inserting new observations...'
INSERT INTO observations (
    observation_uuid, observer_id, latitude, longitude, positional_accuracy,
    taxon_id, quality_grade, observed_on, anomaly_score, origin, version, release
)
SELECT o.observation_uuid, o.observer_id, o.latitude, o.longitude, o.positional_accuracy,
       o.taxon_id, o.quality_grade, o.observed_on, o.anomaly_score, :origin, :version, :release
FROM :stg_schema.observations o
JOIN r2_new_obs n ON n.observation_uuid = o.observation_uuid
WHERE NOT EXISTS (SELECT 1 FROM observations r1 WHERE r1.observation_uuid = o.observation_uuid);

\echo 'Inserted observations:'
SELECT COUNT(*) FROM observations WHERE release = :release AND origin = :origin;

-- Insert photos for new observations
\echo 'Inserting photos for new observations...'
INSERT INTO photos (
    photo_uuid, photo_id, observation_uuid, observer_id,
    extension, license, width, height, position, origin, version, release
)
SELECT p.photo_uuid, p.photo_id, p.observation_uuid, p.observer_id,
       p.extension, p.license, p.width, p.height, p.position, :origin, :version, :release
FROM :stg_schema.photos p
JOIN r2_new_obs n ON n.observation_uuid = p.observation_uuid
WHERE NOT EXISTS (SELECT 1 FROM photos existing WHERE existing.photo_id = p.photo_id);

\echo 'Inserted photos:'
SELECT COUNT(*) FROM photos WHERE release = :release AND origin = :origin;

-- Insert observers referenced by new observations/photos
\echo 'Inserting new observers...'
CREATE TEMP TABLE r2_new_observers AS
SELECT DISTINCT observer_id FROM :stg_schema.observations o
JOIN r2_new_obs n ON n.observation_uuid = o.observation_uuid
WHERE observer_id IS NOT NULL
UNION
SELECT DISTINCT observer_id FROM :stg_schema.photos p
JOIN r2_new_obs n ON n.observation_uuid = p.observation_uuid
WHERE observer_id IS NOT NULL;

INSERT INTO observers (observer_id, login, name, origin, version, release)
SELECT o.observer_id, o.login, o.name, :origin, :version, :release
FROM :stg_schema.observers o
JOIN r2_new_observers n ON n.observer_id = o.observer_id
WHERE NOT EXISTS (SELECT 1 FROM observers existing WHERE existing.observer_id = o.observer_id);

\echo 'Inserted observers:'
SELECT COUNT(*) FROM observers WHERE release = :release AND origin = :origin;

\echo 'r2 delta import complete.'
