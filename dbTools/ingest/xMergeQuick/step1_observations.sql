-- step1_observations.sql
-- Start transaction
BEGIN;

-- Drop table if it exists
DROP TABLE IF EXISTS int_observations_partial;

-- Create intermediate table for observations
CREATE TABLE int_observations_partial (
    observation_uuid uuid NOT NULL,
    observer_id integer,
    latitude numeric(15,10),
    longitude numeric(15,10),
    positional_accuracy integer,
    taxon_id integer,
    quality_grade character varying(255),
    observed_on date,
    origin character varying(255),
    geom public.geometry
);

-- Copy data into the intermediate table
COPY int_observations_partial (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on)
FROM '/metadata/:source/observations.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Create index on observed_on for filtering
CREATE INDEX int_partial_index_observations_observed_on ON int_observations_partial (observed_on);

-- Delete rows with observed_on before the EXCLUDE_BEFORE date
DELETE FROM int_observations_partial WHERE observed_on < ':exclude_before';

-- Add other indexes
CREATE INDEX int_partial_index_observations_observation_uuid ON int_observations_partial (observation_uuid);
CREATE INDEX int_partial_index_observations_observer_id ON int_observations_partial (observer_id);
CREATE INDEX int_partial_index_observations_quality ON int_observations_partial (quality_grade);
CREATE INDEX int_partial_index_observations_taxon_id ON int_observations_partial (taxon_id);

-- Add primary key constraint
ALTER TABLE int_observations_partial ADD CONSTRAINT int_observations_partial_pkey PRIMARY KEY (observation_uuid);

-- Update the 'origin' for the observations
UPDATE int_observations_partial SET origin = ':origins';

-- Commit the transaction
COMMIT;