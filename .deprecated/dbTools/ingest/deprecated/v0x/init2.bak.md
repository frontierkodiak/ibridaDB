```sql
CREATE DATABASE "ibrida-v0" WITH TEMPLATE template_postgis OWNER postgres;

\c ibrida-v0

CREATE TABLE observations (
    observation_uuid uuid NOT NULL,
    observer_id integer,
    latitude numeric(15,10),
    longitude numeric(15,10),
    positional_accuracy integer,
    taxon_id integer,
    quality_grade character varying(255),
    observed_on date
);

CREATE TABLE photos (
    photo_uuid uuid NOT NULL,
    photo_id integer NOT NULL,
    observation_uuid uuid NOT NULL,
    observer_id integer,
    extension character varying(5),
    license character varying(255),
    width smallint,
    height smallint,
    position smallint
);

CREATE TABLE taxa (
    taxon_id integer NOT NULL,
    ancestry character varying(255),
    rank_level double precision,
    rank character varying(255),
    name character varying(255),
    active boolean
);

CREATE TABLE observers (
    observer_id integer NOT NULL,
    login character varying(255),
    name character varying(255)
);

-- Import:
COPY observations FROM '/metadata/June2024/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '/metadata/June2024/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '/metadata/June2024/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '/metadata/June2024/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;


CREATE INDEX index_photos_photo_uuid ON photos USING btree (photo_uuid);
CREATE INDEX index_photos_observation_uuid ON photos USING btree (observation_uuid);
CREATE INDEX index_photos_position ON photos USING btree (position);
CREATE INDEX index_photos_photo_id ON photos USING btree (photo_id);
CREATE INDEX index_taxa_taxon_id ON taxa USING btree (taxon_id);
CREATE INDEX index_observers_observers_id ON observers USING btree (observer_id);
CREATE INDEX index_observations_observer_id ON observations USING btree (observer_id);
CREATE INDEX index_observations_quality ON observations USING btree (quality_grade);
CREATE INDEX index_observations_taxon_id ON observations USING btree (taxon_id);
CREATE INDEX index_taxa_active ON taxa USING btree (active);
CREATE INDEX index_observations_taxon_id ON observations USING btree (taxon_id);

ALTER TABLE observations ADD COLUMN geom public.geometry;
UPDATE observations SET geom = ST_GeomFromText('POINT(' || longitude || ' ' || latitude || ')', 4326);
CREATE INDEX observations_geom ON observations USING GIST (geom);
VACUUM ANALYZE;

ALTER TABLE taxa ADD COLUMN origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN origin VARCHAR(255);

UPDATE taxa SET origin = 'iNat-June2024';
UPDATE observers SET origin = 'iNat-June2024';
UPDATE observations SET origin = 'iNat-June2024';
UPDATE photos SET origin = 'iNat-June2024';

CREATE INDEX index_taxa_origins ON taxa USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_taxa_name ON taxa USING GIN (to_tsvector('simple', name));
CREATE INDEX index_observers_origins ON observers USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins ON photos USING GIN (to_tsvector('simple', origin));

ALTER TABLE photos ADD COLUMN version VARCHAR(255);
ALTER TABLE observations ADD COLUMN version VARCHAR(255);
ALTER TABLE observers ADD COLUMN version VARCHAR(255);
ALTER TABLE taxa ADD COLUMN version VARCHAR(255);


UPDATE photos SET version = 'v0';
UPDATE observations SET version = 'v0';
UPDATE observers SET version = 'v0';
UPDATE taxa SET version = 'v0';

CREATE INDEX index_photos_version ON photos USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observations_version ON observations USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observers_version ON observers USING GIN (to_tsvector('simple', version));
CREATE INDEX index_taxa_version ON taxa USING GIN (to_tsvector('simple', version));