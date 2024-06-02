-- step1_photos.sql
-- Start transaction
BEGIN;

-- -- Drop table if it exists
DROP TABLE IF EXISTS int_photos;

-- Create intermediate table for photos
CREATE TABLE int_photos (
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
COPY int_photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position)
FROM '/metadata/May2024/photos.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Add indexes
CREATE INDEX int_index_photos_photo_uuid ON int_photos (photo_uuid);
CREATE INDEX int_index_photos_observation_uuid ON int_photos (observation_uuid);
CREATE INDEX int_index_photos_position ON int_photos (position);
CREATE INDEX int_index_photos_photo_id ON int_photos (photo_id);

-- Add primary key constraint
ALTER TABLE int_photos ADD CONSTRAINT int_photos_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);

-- Update the 'origin' for the photos
UPDATE int_photos SET origin = 'iNat-May2024';

-- Commit the transaction
COMMIT;
