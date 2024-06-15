-- step1_pt1_photos.sql

-- Start transaction 1
BEGIN;

-- Drop table if it exists
DROP TABLE IF EXISTS int_photos_partial;

-- Create intermediate table for photos
CREATE TABLE int_photos_partial (
    photo_uuid uuid NOT NULL,
    photo_id integer NOT NULL,
    observation_uuid uuid NOT NULL,
    observer_id integer,
    extension character varying(5),
    license character varying(255),
    width smallint,
    height smallint,
    position smallint,
    origin character varying(255)
);

-- Copy data into the intermediate table
COPY int_photos_partial (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position)
FROM '/metadata/May2024/photos.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Create index on observation_uuid for filtering
CREATE INDEX int_partial_index_photos_observation_uuid ON int_photos_partial (observation_uuid);

-- Commit transaction 1
COMMIT;