-- step3_observations.sql
-- Start a new transaction for merging
BEGIN;

-- Merge observations
INSERT INTO observations
SELECT observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, origin, 
       geom
FROM int_observations_partial
ON CONFLICT (observation_uuid) DO NOTHING;

-- Commit the transaction
COMMIT;

-- Reindex observations table
REINDEX TABLE observations;
