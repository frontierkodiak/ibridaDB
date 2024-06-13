-- step1_photos.sql part 2

-- Start transaction 2
BEGIN;

-- Delete photos that do not have a corresponding observation
DELETE FROM int_photos_partial
WHERE observation_uuid NOT IN (SELECT observation_uuid FROM int_observations_partial);

-- Commit transaction 2
COMMIT;

-- Start transaction 3
BEGIN;

-- Add other indexes
CREATE INDEX int_partial_index_photos_photo_uuid ON int_photos_partial (photo_uuid);
CREATE INDEX int_partial_index_photos_position ON int_photos_partial (position);
CREATE INDEX int_partial_index_photos_photo_id ON int_photos_partial (photo_id);

-- Commit transaction 3
COMMIT;

-- Start transaction 4
BEGIN;

-- Add primary key constraint
ALTER TABLE int_photos_partial ADD CONSTRAINT int_photos_partial_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);

-- Update the 'origin' for the photos
UPDATE int_photos_partial SET origin = ':origins';

-- Commit transaction 4
COMMIT;