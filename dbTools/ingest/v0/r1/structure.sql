-- Structure for v0r1 (December 2024 release)
-- Note: anomaly_score column added in r1, not present in r0

CREATE TABLE observations (
    observation_uuid uuid NOT NULL,
    observer_id integer,
    latitude numeric(15,10),
    longitude numeric(15,10),
    positional_accuracy integer,
    taxon_id integer,
    quality_grade character varying(255),
    observed_on date,
    anomaly_score numeric(15,6)  -- New column in r1
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

-- Note: The following columns are added by our ingestion process:
-- All tables:
--   origin VARCHAR(255)
--   version VARCHAR(255)
--   release VARCHAR(255)
-- Observations table:
--   geom public.geometry