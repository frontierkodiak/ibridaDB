-- Start transaction
BEGIN;

-- Create temporary tables
CREATE TEMP TABLE temp_observations (LIKE observations INCLUDING ALL);
CREATE TEMP TABLE temp_photos (LIKE photos INCLUDING ALL);
CREATE TEMP TABLE temp_observers (LIKE observers INCLUDING ALL);

-- Copy data into temporary tables, accommodating cols not found in CSVs
COPY temp_photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position) FROM '/metadata/May2024/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY temp_observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on) FROM '/metadata/May2024/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY temp_observers (observer_id, login, name) FROM '/metadata/May2024/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Update the 'origin' for all tables and calculate 'geom' for observations
UPDATE temp_observations SET
    origin = 'iNat-May2024',
    geom = ST_GeomFromText('POINT(' || longitude || ' ' || latitude || ')', 4326);

UPDATE temp_photos SET origin = 'iNat-May2024';
UPDATE temp_observers SET origin = 'iNat-May2024';

-- Merge observations
INSERT INTO observations SELECT * FROM temp_observations
ON CONFLICT (observation_uuid) DO NOTHING;

-- Merge photos
INSERT INTO photos SELECT * FROM temp_photos
ON CONFLICT (photo_uuid, photo_id, position, observation_uuid) DO NOTHING;

-- Merge observers
INSERT INTO observers SELECT * FROM temp_observers
ON CONFLICT (observer_id) DO NOTHING;

-- Commit the transaction if all operations succeed
COMMIT;

-- Drop temporary tables if transaction is successful
DROP TABLE temp_observations;
DROP TABLE temp_photos;
DROP TABLE temp_observers;

-- Reindex tables
REINDEX TABLE observations;
REINDEX TABLE photos;
REINDEX TABLE observers;