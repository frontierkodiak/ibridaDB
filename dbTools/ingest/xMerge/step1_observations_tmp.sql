-- step1_observations.sql
-- Start transaction
BEGIN;

-- -- Drop table if it exists
DROP TABLE IF EXISTS int_observations;

-- Create intermediate table for observations
CREATE TABLE int_observations (
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
COPY int_observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on)
FROM '/metadata/May2024/observations.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Add indexes
CREATE INDEX int_index_observations_observation_uuid ON int_observations (observation_uuid);
CREATE INDEX int_index_observations_observer_id ON int_observations (observer_id);
CREATE INDEX int_index_observations_quality ON int_observations (quality_grade);
CREATE INDEX int_index_observations_taxon_id ON int_observations (taxon_id);

-- Add primary key constraint
ALTER TABLE int_observations ADD CONSTRAINT int_observations_pkey PRIMARY KEY (observation_uuid);

-- Update the 'origin' for the observations
UPDATE int_observations SET origin = 'iNat-May2024';

-- Commit the transaction
COMMIT;
