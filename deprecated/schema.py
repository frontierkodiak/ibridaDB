# ibridaDB/schema.py
from sqlalchemy import (
    Boolean,
    Column,
    Date,
    Float,
    ForeignKey,
    Integer,
    Numeric,
    SmallInteger,
    String,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

# NOTE: Some tables do not include origin.
# NOTE: Some tables also include a column for version.

### TODO: Migrate to new `models/` folder. However, not `taxa/models/` as this is specific to generated taxa tables (dervided from below taxa table, or ColDP   )
## NOTE: Below are the base iNaturalist tables, corresponding to the structure.sql directly from the iNaturalist Open Data dump.


class Observations(Base):
    __tablename__ = "observations"
    observation_uuid = Column(UUID(as_uuid=True), primary_key=True)
    observer_id = Column(Integer)
    latitude = Column(Numeric(precision=15, scale=10))
    longitude = Column(Numeric(precision=15, scale=10))
    positional_accuracy = Column(Integer)
    taxon_id = Column(Integer)
    quality_grade = Column(String)
    observed_on = Column(Date)
    origin = Column(String)
    # NOTE: Does not include geom column


class Photos(Base):
    __tablename__ = "photos"
    photo_uuid = Column(UUID(as_uuid=True), primary_key=True)
    photo_id = Column(Integer, primary_key=True)
    observation_uuid = Column(
        UUID(as_uuid=True), ForeignKey("observations.observation_uuid")
    )
    observer_id = Column(Integer)
    extension = Column(String(5))
    license = Column(String)
    width = Column(SmallInteger)
    height = Column(SmallInteger)
    position = Column(SmallInteger)
    origin = Column(String)


class Taxa(Base):
    __tablename__ = "taxa"
    taxon_id = Column(Integer, primary_key=True)
    ancestry = Column(String)
    rank_level = Column(
        Float
    )  # Assuming double precision is adequately represented by Float
    rank = Column(String)
    name = Column(String)
    active = Column(Boolean)
    origin = Column(String)


class TaxaTemp(Base):
    __tablename__ = "taxa_temp"
    taxon_id = Column(Integer, primary_key=True)
    ancestry = Column(String)
    rank_level = Column(Float)  # Same assumption as Taxa
    rank = Column(String)
    name = Column(String)
    active = Column(Boolean)


class Observers(Base):
    __tablename__ = "observers"
    observer_id = Column(Integer, primary_key=True)
    login = Column(String)
    name = Column(String)
    origin = Column(String)


"""
Above needs to match with following structure of existing tables in 'postgres' db:

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
-- Indexes:
CREATE INDEX index_photos_photo_uuid ON photos USING btree (photo_uuid);
CREATE INDEX index_photos_observation_uuid ON photos USING btree (observation_uuid);
CREATE INDEX index_taxa_taxon_id ON taxa USING btree (taxon_id);
CREATE INDEX index_observers_observers_id ON observers USING btree (observer_id);
CREATE INDEX index_observations_observer_id ON observations USING btree (observer_id);
CREATE INDEX index_observations_quality ON observations USING btree (quality_grade);
CREATE INDEX index_observations_taxon_id ON taxa USING btree (taxon_id);
-- 'Origins' for versioning:
ALTER TABLE taxa ADD COLUMN origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN origin VARCHAR(255);

UPDATE taxa SET origin = 'iNat-June2023';
UPDATE observers SET origin = 'iNat-June2023';
UPDATE observations SET origin = 'iNat-June2023';
UPDATE photos SET origin = 'iNat-June2023';

CREATE INDEX index_taxa_origins ON taxa USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observers_origins ON observers USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins ON photos USING GIN (to_tsvector('simple', origin));
"""
