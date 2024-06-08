-- step1_photos.sql
-- Start transaction
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
FROM '/metadata/:source/photos.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Create index on observation_uuid for filtering
CREATE INDEX int_partial_index_photos_observation_uuid ON int_photos_partial (observation_uuid);

-- Delete photos that do not have a corresponding observation
DELETE FROM int_photos_partial
WHERE observation_uuid NOT IN (SELECT observation_uuid FROM int_observations_partial);

-- Add other indexes
CREATE INDEX int_partial_index_photos_photo_uuid ON int_photos_partial (photo_uuid);
CREATE INDEX int_partial_index_photos_position ON int_photos_partial (position);
CREATE INDEX int_partial_index_photos_photo_id ON int_photos_partial (photo_id);

-- Add primary key constraint
ALTER TABLE int_photos_partial ADD CONSTRAINT int_photos_partial_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);

-- Update the 'origin' for the photos
UPDATE int_photos_partial SET origin = ':origins';

-- Commit the transaction
COMMIT;