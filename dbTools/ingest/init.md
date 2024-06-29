## First-time ingest 
*First-time ingest, using iNat open data dump from June2023 (iNatJune2023).*

Start PostGIS container:
```bash
docker run -d --name ibrida \
  --shm-size=16g \
  -e POSTGRES_PASSWORD=password \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -e POSTGRES_SHARED_BUFFERS=8GB \
  -e POSTGRES_WORK_MEM=2048MB \
  -e POSTGRES_MAINTENANCE_WORK_MEM=4GB \
  -v /ibrida/postgresql:/var/lib/postgresql/data \
  -v /pond/Polli/ibridaExports:/exports \
  -v /ibrida/queries:/queries \
  -v /ibrida/metadata:/metadata \
  -p 5432:5432 \
  postgis/postgis:15-3.3

docker start ibrida

docker exec -ti ibrida psql -U postgres
```

Setup S3:
```bash
aws configure
...
```

Import iNat metadata into Ibrida:
```sql
-- bash into psql:
docker exec -ti ibrida psql -U postgres

-- Create new database
### NOTE #### The real database, for whatever reason, is actually named 'postgres'!!
CREATE DATABASE "inaturalist-open-data" WITH TEMPLATE template_postgis OWNER postgres;
-- apply structure
--- Just open structure.sql and run these commands manually..
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
COPY observations FROM '/metadata/inaturalist-open-data-20230627/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '/metadata/inaturalist-open-data-20230627/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '/metadata/inaturalist-open-data-20230627/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '/metadata/inaturalist-open-data-20230627/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
```

Make indices:
```sql
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
```
Add geometry:
```sql
ALTER TABLE observations ADD COLUMN geom public.geometry;
UPDATE observations SET geom = ST_GeomFromText('POINT(' || longitude || ' ' || latitude || ')', 4326);
CREATE INDEX observations_geom ON observations USING GIST (geom);
VACUUM ANALYZE;
```
Adding 'origins' tag for versioning the pull date from iNat
```sql
ALTER TABLE taxa ADD COLUMN origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN origin VARCHAR(255);

UPDATE taxa SET origin = 'iNat-June2023';
UPDATE observers SET origin = 'iNat-June2023';
UPDATE observations SET origin = 'iNat-June2023';
UPDATE photos SET origin = 'iNat-June2023';

CREATE INDEX index_taxa_origins ON taxa USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_taxa_name ON taxa USING GIN (to_tsvector('simple', name));
CREATE INDEX index_observers_origins ON observers USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins ON photos USING GIN (to_tsvector('simple', origin));
```

Add 'version' tag for version with the ibrida-pulls schema (used downstream).
```sql
ALTER TABLE photos ADD COLUMN version VARCHAR(255);
ALTER TABLE observations ADD COLUMN version VARCHAR(255);
ALTER TABLE observers ADD COLUMN version VARCHAR(255);
ALTER TABLE taxa ADD COLUMN version VARCHAR(255);


UPDATE photos SET version = 'v1';
UPDATE observations SET version = 'v1';
UPDATE observers SET version = 'v1';
UPDATE taxa SET version = 'v1';

CREATE INDEX index_photos_version ON photos USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observations_version ON observations USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observers_version ON observers USING GIN (to_tsvector('simple', version));
CREATE INDEX index_taxa_version ON taxa USING GIN (to_tsvector('simple', version));

-- Verify
SELECT DISTINCT version FROM photos;
SELECT DISTINCT version FROM observations;
```

Explicitly set primary keys on master tables:
```sql
-- Add primary key to observations
ALTER TABLE observations
ADD CONSTRAINT observations_pkey PRIMARY KEY (observation_uuid);

-- Add primary key to photos
ALTER TABLE photos
ADD CONSTRAINT photos_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);

-- Add primary key to observers
ALTER TABLE observers
ADD CONSTRAINT observers_pkey PRIMARY KEY (observer_id);

-- Add primary key to taxa
ALTER TABLE taxa
ADD CONSTRAINT taxa_pkey PRIMARY KEY (taxon_id);


--- Inspect
----- See primary key definition
SELECT conname AS constraint_name, 
       pg_get_constraintdef(c.oid) AS constraint_definition
FROM   pg_constraint c
JOIN   pg_namespace n ON n.oid = c.connamespace
JOIN   pg_class cl ON cl.oid = c.conrelid
WHERE  cl.relname = 'photos' AND c.contype = 'p';
------- Why photos table "position" col surrounded by quotes?