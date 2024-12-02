



# Sequence

## Step 0: Setup vars
TODO: Modify all commands to use these vars.
Verify that this is the correct date format.
TODO: Are filter start/end dates inclusive? Might need to udpate dates.
```bash
DB_NAME="ibrida-v1"
ORIGIN="iNat-June2024"
GEOM_NUM_PROCESSES=16
GEOM_TABLE_NAME="observations"
SPLIT_0_VERS="v1s0"
SPLIT_0_END_DATE="2021-06-30"
SPLIT_1_VERS="v1s1"
SPLIT_1_END_DATE="2022-06-30"
SPLIT_2_VERS="v1s2"
SPLIT_2_END_DATE="2023-06-30"
SPLIT_3_VERS="v1s3"
SPLIT_3_END_DATE="2024-06-30"
```
We later split the exports to make downstream processing easier.
    Note: Split N contains the rows starting at N-1 end date, up to N end date.
    Split 0 contains all rows before the first end date.
We set the versions for each split at the very end of the process, then export to the proper version subdir.

## Step 1: Start container

```bash
Start PostGIS container:
```bash
# New, fast NVME storage
docker run -d --name ibrida \
  --shm-size=16g \
  -e POSTGRES_PASSWORD=password \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -e POSTGRES_SHARED_BUFFERS=8GB \
  -e POSTGRES_WORK_MEM=2048MB \
  -e POSTGRES_MAINTENANCE_WORK_MEM=4GB \
  -v ~/repo/ibridaDB/dbTools:/tool \
  -v ~/repo/ibridaDB/dbQueries:/query \
  -v /peach/ibrida2:/var/lib/postgresql/data \
  -v /pond/Polli/ibridaExports:/exports \
  -v /ibrida/metadata:/metadata \
  -p 5432:5432 \
  postgis/postgis:15-3.3

docker start ibrida

docker exec -ti ibrida psql -U postgres
```

## Step 2: Create database, apply schema

```sql
CREATE DATABASE "ibrida-v1" WITH TEMPLATE template_postgis OWNER postgres;

\c ibrida-v1

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
```

## Step 3: Load in data
*NOTE:* Can run in parallel.
```sql
COPY observations FROM '/metadata/June2024/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '/metadata/June2024/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '/metadata/June2024/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '/metadata/June2024/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
```

## Step 4: Calculate geom on observations
*Calculate in parallel with geom.sh.*
    Takes args: DB_NAME, TABLE_NAME, NUM_PROCESSES, BASE_DIR
    BASE_DIR can be hardcoded to `BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v1"`

## Step 5: Add indices

## Step 6: Add observed_on col to photos
Pair photos with their observation.observed_on by matching on observation_uuid.

### Step 6.1: Add observed_on index to photos

## Step 7: Add custom columns to tables.
Adding origin to observations, photos, taxa, observers.
Adding version to observations, photos.

### Step 7.1: Set origin to `$ORIGIN` for all rows on all tables.

### Step 7.2: Set version tags on observations, photos.
Calculate version tags based on the `observed_on` date.

TODO: Implement
Implementation... propose and suggest an implementation based on the following:

```
# We create 4 splits; values are vars but here are examples (we'll use these for this run of the script):
SPLIT_0_VERS="v1s0"
SPLIT_0_END_DATE="2021-06-30"
SPLIT_1_VERS="v1s1"
SPLIT_1_END_DATE="2022-06-30"
SPLIT_2_VERS="v1s2"
SPLIT_2_END_DATE="2023-06-30"
SPLIT_3_VERS="v1s3"
SPLIT_3_END_DATE="2024-06-30"
```
We later split the exports to make downstream processing easier.
    Note: Split N contains the rows starting at N-1 end date, up to N end date.
    Split 0 contains all rows before the first end date.
We set the versions for each split at the very end of the process, then export to the proper version subdir.

### Step 7.3: Add origin, version indices.
Add origin indices to observations, photos, taxa, observers.
Add version indices to observations, photos.


## Step 8: Run queries to generate child tables.

### Step 8.1: Create NAfull_min50all_taxa, NAfull_min50all_taxa_obs
TODO: Execute /home/caleb/repo/ibridaDB/dbQueries/NA/full/base.sql script.
TODO: Modify this script to include the 'version' field from observations on output NAfull_min50all_taxa_obs. 

### Step 8.1: Create per-taxa child tables
TODO: Execute /home/caleb/repo/ibridaDB/dbQueries/NA/full/children.sql
TODO: Modify this script to include the 'version' field from observations on output NAfull_<taxa>_min50all_cap4000_photos tables.
TODO: Remove the copy commands from end of script.

### Step 8.2: Create per-version child tables from per-taxa tables.

## Step 9: Copy per-version, per-taxa tables to /exports/<ORIGIN>/<VERSION>/<table_name>.csv
TODO: Make a script to wrap the copy commands, taking above args to form out path.


## Optional steps:
NOTE: Ignore optional steps for now.
### Create primary keys
This is very, very slow. If you want to do this, ensure that you commit previous transactions first, as the machine is likely to shutdown before this finishes!
    Can run all 4 in parallel. But be warned: even with indices, photos takes 1wk+.
```sql
ADD CONSTRAINT observations_pkey PRIMARY KEY (observation_uuid);
ALTER TABLE photos ADD CONSTRAINT photos_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);
ALTER TABLE taxa ADD CONSTRAINT taxa_pkey PRIMARY KEY (taxon_id);
ALTER TABLE observers ADD CONSTRAINT observers_pkey PRIMARY KEY (observer_id);
```
