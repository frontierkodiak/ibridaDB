-- step3_observers.sql
-- Start a new transaction for merging
BEGIN;

-- Merge observers
INSERT INTO observers
SELECT observer_id, login, name, origin
FROM int_observers_partial
ON CONFLICT (observer_id) DO NOTHING;

-- Commit the transaction
COMMIT;

-- Reindex observers table
REINDEX TABLE observers;
