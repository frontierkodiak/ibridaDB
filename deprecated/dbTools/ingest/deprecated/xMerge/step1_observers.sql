-- step1_observers.sql
-- Start transaction
BEGIN;

-- -- Drop table if it exists
DROP TABLE IF EXISTS int_observers;

-- Create intermediate table for observers
CREATE TABLE int_observers (
    observer_id integer NOT NULL,
    login character varying(255),
    name character varying(255),
    origin character varying(255)
);

-- Copy data into the intermediate table
COPY int_observers (observer_id, login, name)
FROM '/metadata/:source/observers.csv'
DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

-- Add indexes
CREATE INDEX int_index_observers_observer_id ON int_observers (observer_id);

-- Add primary key constraint
ALTER TABLE int_observers ADD CONSTRAINT int_observers_pkey PRIMARY KEY (observer_id);

-- Update the 'origin' for the observers
UPDATE int_observers SET origin = ':origins';

-- Commit the transaction
COMMIT;
