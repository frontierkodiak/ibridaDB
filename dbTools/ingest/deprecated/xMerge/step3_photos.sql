-- step3_photos.sql
-- Start a new transaction for merging
BEGIN;

-- Merge photos
INSERT INTO photos
SELECT photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position, origin
FROM int_photos
ON CONFLICT (photo_uuid, photo_id, position, observation_uuid) DO NOTHING;

-- Commit the transaction
COMMIT;

-- Reindex photos table
REINDEX TABLE photos;
