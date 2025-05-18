#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# expand_taxa.sh
# -----------------------------------------------------------------------------
# Creates a new "expanded_taxa" table by expanding ancestry from the existing
# "taxa" table into structured columns ("L{level}_taxonID", "L{level}_name", etc.).
#
# This version uses *string concatenation* with quote_ident(...) and quote_nullable(...),
# bypassing placeholders entirely. This is the "sure" approach: no risk of
# placeholders vanishing, since we embed the actual values directly into the
# final SQL string.
#
# Steps:
#   1) Drop 'expanded_taxa' if exists; create base columns with quotes.
#   2) Add columns for each rank level ("L5_taxonID", "L5_name", etc.).
#   3) Create expand_taxa_procedure() as a function:
#      - We skip rank levels not in RANK_LEVELS (no 100).
#      - If debugging is enabled (DEBUG_EXPAND_TAXA=true), we RAISE NOTICE
#        about the row's data and the final SQL statement.
#      - We *string-concatenate* the column references, so no placeholders are used.
#   4) SELECT expand_taxa_procedure() to populate the table.
#   5) Create indexes on "L10_taxonID"... "L70_taxonID", plus "taxonID", "rankLevel", "name".
#   6) VACUUM (ANALYZE), notifications, done.
#
# Usage:
#   DEBUG_EXPAND_TAXA=true ./expand_taxa.sh
# -----------------------------------------------------------------------------

# ===[ 1) Setup & Logging ]====================================================
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/$(basename "$0" .sh)_$(date +%Y%m%d_%H%M%S).log"
echo "Starting new run at $(date)" > "${LOG_FILE}"

# Log messages (with timestamps) to both console and file
log_message() {
    local timestamp
    timestamp="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    echo "[$timestamp] $1" | tee -a "${LOG_FILE}"
}

# Redirect stdout/stderr to console+log
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}")

# Source your common functions (for execute_sql, send_notification, etc.)
source "/home/caleb/repo/ibridaDB/dbTools/export/v0/common/functions.sh"

# Environment / defaults
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_NAME="${DB_NAME:-ibrida-v0-r1}"
DB_USER="${DB_USER:-postgres}"

# If DEBUG_EXPAND_TAXA=true, we pass a GUC variable into Postgres to enable debug
DEBUG_EXPAND="${DEBUG_EXPAND_TAXA:-false}"  # "true" or "false"

# rank levels to expand (no 100). We'll handle 5, 10, 11, ... 70
RANK_LEVELS=(5 10 11 12 13 15 20 24 25 26 27 30 32 33 33.5 34 34.5 35 37 40 43 44 45 47 50 53 57 60 67 70)

# We'll create indexes only on L10..L70
INDEX_LEVELS=(10 20 30 40 50 60 70)

log_message "Beginning expand_taxa.sh for DB: ${DB_NAME} (DEBUG_EXPAND_TAXA=${DEBUG_EXPAND})"

# ===[ 2) Create expanded_taxa schema ]========================================
log_message "Step 1: Dropping old expanded_taxa and creating base columns with quotes."

execute_sql "
DROP TABLE IF EXISTS \"expanded_taxa\" CASCADE;
CREATE TABLE \"expanded_taxa\" (
    \"taxonID\"       INTEGER PRIMARY KEY,
    \"rankLevel\"     DOUBLE PRECISION,
    \"rank\"          VARCHAR(255),
    \"name\"          VARCHAR(255),
    \"commonName\"    VARCHAR(255),
    \"taxonActive\"   BOOLEAN
    -- We'll add \"LXX_taxonID\", \"LXX_name\", \"LXX_commonName\" columns next
);
"

# ===[ 3) Add columns for each rank level ]====================================
log_message "Step 2: Adding L{level}_taxonID, L{level}_name, L{level}_commonName columns."

ADD_COLS=""
for L in "${RANK_LEVELS[@]}"; do
  SAFE_L=$(echo "${L}" | sed 's/\./_/g')
  ADD_COLS+=" ADD COLUMN \"L${SAFE_L}_taxonID\" INTEGER,
             ADD COLUMN \"L${SAFE_L}_name\" VARCHAR(255),
             ADD COLUMN \"L${SAFE_L}_commonName\" VARCHAR(255),"
done

# Remove trailing comma
ADD_COLS="${ADD_COLS%,}"

execute_sql "
ALTER TABLE \"expanded_taxa\"
${ADD_COLS};
"

# ===[ 4) Create expand_taxa_procedure() function ]============================
log_message "Step 3: Creating expand_taxa_procedure() with string-concatenation for dynamic columns."

# We'll incorporate a GUC "myapp.debug_expand" to signal debug mode in PL/pgSQL
if [ "${DEBUG_EXPAND}" = "true" ]; then
  execute_sql "SET myapp.debug_expand = 'on';"
else
  execute_sql "SET myapp.debug_expand = 'off';"
fi

execute_sql "
DROP FUNCTION IF EXISTS expand_taxa_procedure() CASCADE;

CREATE OR REPLACE FUNCTION expand_taxa_procedure()
RETURNS void
LANGUAGE plpgsql
AS \$\$
DECLARE
    t_rec RECORD;
    ancestor_ids TEXT[];
    this_ancestor TEXT;
    anc_data RECORD;
    effective_level TEXT;
    row_sql TEXT;
    debugging boolean := false;
BEGIN
    -- We'll read our GUC to see if debug is on
    BEGIN
        IF current_setting('myapp.debug_expand') = 'on' THEN
            debugging := true;
        END IF;
    EXCEPTION
        WHEN others THEN
            debugging := false;  -- if the GUC is not set, do nothing
    END;

    -- Only retrieve active taxa rows, ignoring inactive ones
    FOR t_rec IN
        SELECT taxon_id, ancestry, rank_level, rank, name, active
        FROM taxa
        WHERE active = true
    LOOP
        -- Insert base row
        INSERT INTO \"expanded_taxa\"(\"taxonID\", \"rankLevel\", \"rank\", \"name\", \"taxonActive\")
        VALUES (t_rec.taxon_id, t_rec.rank_level, t_rec.rank, t_rec.name, t_rec.active);

        IF t_rec.ancestry IS NOT NULL AND t_rec.ancestry <> '' THEN
            ancestor_ids := string_to_array(t_rec.ancestry, '/');
        ELSE
            ancestor_ids := ARRAY[]::TEXT[];
        END IF;

        -- Include self
        ancestor_ids := ancestor_ids || t_rec.taxon_id::TEXT;

        FOREACH this_ancestor IN ARRAY ancestor_ids
        LOOP
            BEGIN
                IF this_ancestor IS NULL THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping NULL ancestor for row taxon_id=%', t_rec.taxon_id;
                    END IF;
                    CONTINUE;
                END IF;

                SELECT rank_level, rank, name
                  INTO anc_data
                  FROM taxa
                 WHERE taxon_id = this_ancestor::INTEGER
                 LIMIT 1;

                IF NOT FOUND OR anc_data.name IS NULL THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping ancestor=% for row taxon_id=%: not found or name is NULL', this_ancestor, t_rec.taxon_id;
                    END IF;
                    CONTINUE;
                END IF;

                IF anc_data.rank_level NOT IN (
                    5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30,
                    32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45,
                    47, 50, 53, 57, 60, 67, 70
                ) THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping rank_level=% for row taxon_id=% (ancestor=%)', anc_data.rank_level, t_rec.taxon_id, this_ancestor;
                    END IF;
                    CONTINUE;
                END IF;

                effective_level := replace(CAST(anc_data.rank_level AS TEXT), '.', '_');

                -- Build dynamic SQL via string concat + quote_ident(...) + quote_nullable(...)
                row_sql :=
                    'UPDATE \"expanded_taxa\" SET '
                    || quote_ident('L' || effective_level || '_taxonID') || ' = '
                        || quote_nullable(this_ancestor)
                    || ', '
                    || quote_ident('L' || effective_level || '_name') || ' = '
                        || quote_nullable(anc_data.name)
                    || ' WHERE \"taxonID\" = ' || quote_nullable(t_rec.taxon_id::text);

                IF debugging THEN
                    RAISE NOTICE 'Row taxon_id=% => rank_level=% => built SQL: %',
                                 t_rec.taxon_id, anc_data.rank_level, row_sql;
                END IF;

                EXECUTE row_sql;

            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Error updating row => base taxon_id=%, ancestor=%, anc_data=(%,%,%), row_sql=[%]',
                  t_rec.taxon_id, this_ancestor, anc_data.rank_level, anc_data.rank, anc_data.name, row_sql;
                RAISE;
            END;
        END LOOP;
    END LOOP;
END;
\$\$;
"

# ===[ 5) Populate expanded_taxa ]=============================================
log_message "Step 4: SELECT expand_taxa_procedure() to populate."

execute_sql "
SELECT expand_taxa_procedure();
"

log_message "Population of expanded_taxa complete. Running: \\d \"expanded_taxa\""
execute_sql "\d \"expanded_taxa\""

send_notification "expand_taxa.sh: Step 4 complete (expanded_taxa populated)."

# ===[ 6) Create indexes (only on L10..L70) ]===================================
log_message "Step 5: Creating indexes on L10_taxonID, L20_taxonID, ..., L70_taxonID plus base columns."

for L in "${INDEX_LEVELS[@]}"; do
  SAFE_L=$(echo "${L}" | sed 's/\./_/g')
  execute_sql "
  CREATE INDEX IF NOT EXISTS idx_expanded_taxa_L${SAFE_L}_taxonID
    ON \"expanded_taxa\"(\"L${SAFE_L}_taxonID\");
  "
done

execute_sql "
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_taxonID    ON \"expanded_taxa\"(\"taxonID\");
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_rankLevel  ON \"expanded_taxa\"(\"rankLevel\");
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_name       ON \"expanded_taxa\"(\"name\");
"

log_message "Index creation done. Running: \\d \"expanded_taxa\""
execute_sql "\d \"expanded_taxa\""

send_notification "expand_taxa.sh: Step 5 complete (indexes created)."

# ===[ 7) VACUUM ANALYZE ]====================================================
log_message "Step 6: VACUUM ANALYZE \"expanded_taxa\" (final step)."

execute_sql "
VACUUM (ANALYZE) \"expanded_taxa\";
"

send_notification "expand_taxa.sh: Step 6 complete (VACUUM ANALYZE done)."
log_message "expand_taxa.sh complete. Exiting."
