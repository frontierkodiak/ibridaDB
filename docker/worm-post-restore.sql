-- Post-restore initialization for ibridaDB on worm
-- Run after pg_restore completes

-- Enable pg_stat_statements for otel observability
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create otel monitoring role (least-privilege)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'otel_monitor') THEN
    CREATE USER otel_monitor WITH PASSWORD 'otel-ibridadb-worm';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE "ibrida-v0-r2" TO otel_monitor;
GRANT USAGE ON SCHEMA public TO otel_monitor;
GRANT pg_read_all_stats TO otel_monitor;

-- Run ANALYZE on all tables for fresh planner stats
ANALYZE;
