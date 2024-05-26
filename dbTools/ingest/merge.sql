-- Start transaction
BEGIN;

-- Create temporary tables without primary key constraints
CREATE TEMP TABLE temp_observations (
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

CREATE TEMP TABLE temp_photos (
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

CREATE TEMP TABLE temp_observers (
    observer_id integer NOT NULL,
    login character varying(255),
    name character varying(255),
    origin character varying(255)
);

-- Copy data into temporary tables
COPY temp_observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on)
FROM '/metadata/May2024/observations.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

COPY temp_photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position)
FROM '/metadata/May2024/photos.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

COPY temp_observers (observer_id, login, name)
FROM '/metadata/May2024/observers.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Add indexes to the temporary tables
CREATE INDEX temp_index_temp_photos_photo_uuid ON temp_photos (photo_uuid);
CREATE INDEX temp_index_temp_photos_observation_uuid ON temp_photos (observation_uuid);
CREATE INDEX temp_index_temp_photos_position ON temp_photos (position);
CREATE INDEX temp_index_temp_photos_photo_id ON temp_photos (photo_id);
CREATE INDEX temp_index_temp_observations_observation_uuid ON temp_observations (observation_uuid);
CREATE INDEX temp_index_temp_observations_observer_id ON temp_observations (observer_id);
CREATE INDEX temp_index_temp_observations_quality ON temp_observations (quality_grade);
CREATE INDEX temp_index_temp_observations_taxon_id ON temp_observations (taxon_id);
CREATE INDEX temp_index_temp_observers_observer_id ON temp_observers (observer_id);

-- Add primary key constraints to the temporary tables
ALTER TABLE temp_observations ADD CONSTRAINT temp_observations_pkey PRIMARY KEY (observation_uuid);
ALTER TABLE temp_photos ADD CONSTRAINT temp_photos_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);
ALTER TABLE temp_observers ADD CONSTRAINT temp_observers_pkey PRIMARY KEY (observer_id);

VACUUM ANALYZE temp_observations;
VACUUM ANALYZE temp_photos;
VACUUM ANALYZE temp_observers;

-- Update the 'origin' for all tables and calculate 'geom' for observations
UPDATE temp_observations SET
    origin = 'iNat-May2024',
    geom = ST_GeomFromText('POINT(' || longitude || ' ' || latitude || ')', 4326);

UPDATE temp_photos SET origin = 'iNat-May2024';
UPDATE temp_observers SET origin = 'iNat-May2024';

-- Vacuum and analyze the tables
VACUUM ANALYZE observations;
VACUUM ANALYZE photos;
VACUUM ANALYZE observers;

VACUUM ANALYZE temp_observations;
VACUUM ANALYZE temp_photos;
VACUUM ANALYZE temp_observers;

-- Merge observations
INSERT INTO observations
SELECT * FROM temp_observations
ON CONFLICT (observation_uuid) DO NOTHING;

-- Merge photos
INSERT INTO photos
SELECT * FROM temp_photos
ON CONFLICT (photo_uuid, photo_id, position, observation_uuid) DO NOTHING;

-- Merge observers
INSERT INTO observers
SELECT * FROM temp_observers
ON CONFLICT (observer_id) DO NOTHING;

-- Commit the transaction if all operations succeed
COMMIT;

-- Drop temporary tables if transaction is successful
DROP TABLE temp_observations;
DROP TABLE temp_photos;
DROP TABLE temp_observers;

-- Reindex master tables
REINDEX TABLE observations;
REINDEX TABLE photos;
REINDEX TABLE observers;