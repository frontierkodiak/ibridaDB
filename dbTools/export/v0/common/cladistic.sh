#!/bin/bash
# ------------------------------------------------------------------------------
# cladistic.sh
# ------------------------------------------------------------------------------
# Creates filtered observation subsets for a specified clade/metaclade,
# referencing the "expanded_taxa" table instead of the old recursive string method.
#
# Usage pattern:
#   1) Environment variables set by an upstream wrapper or main script:
#      - METACLADE=...
#      - CLADE=...
#      - MACROCLADE=...
#      - DB_CONTAINER, DB_USER, DB_NAME
#      - REGION_TAG, MIN_OBS, ...
#   2) We load "clade_defns.sh" to define which integer columns to match
#      (e.g. "L50_taxonID" = 47120).
#   3) We create a final table <group>_observations joined to expanded_taxa
#      so only active, recognized taxonIDs appear.
#   4) We then export to CSV with a random subset of photos. 
#      The new requirement: we must include the entire ancestral taxonID set
#      (L5_taxonID, L10_taxonID, ... L70_taxonID) plus expanded_taxa.taxonID,
#      expanded_taxa.rankLevel, and expanded_taxa.name. 
#   5) The environment variable "EXPORT_GROUP" is used to name the final table
#      and output CSV (e.g. "primary_terrestrial_arthropoda").
#
# IMPORTANT NOTE regarding CSV exports:
#   - The script now appends every L{level}_taxonID column and the base columns
#     (taxonID, rankLevel, name from expanded_taxa) to the standard observation
#     columns plus photo fields. This ensures our downstream processes have
#     all needed ancestry info.
#
# ------------------------------------------------------------------------------
# Permission / Ownership Note:
#   If you see "Operation not permitted" when chmod-ing existing CSV files, it
#   usually means the container user (UID 998) cannot change permissions on a
#   file already owned by another user. As long as the directory is world-writable
#   (e.g. drwxrwxrwx) and the file is not locked down, Postgres should still be
#   able to write new CSV data. However, if you see actual "permission denied"
#   errors at export time, confirm the directory and file ownership allow writes.
# ------------------------------------------------------------------------------

# Load shared functions (execute_sql, print_progress, get_obs_columns, etc.)
source "${BASE_DIR}/common/functions.sh"

# Load the new clade definitions (MACROCLADES, CLADES, METACLADES, get_clade_condition)
source "${BASE_DIR}/common/clade_defns.sh"

# 1) Construct the final condition from environment variables
CLADE_CONDITION="$(get_clade_condition)"

print_progress "Creating filtered tables for ${EXPORT_GROUP}"

# We'll build the final table name, e.g. "primary_terrestrial_arthropoda_observations"
TABLE_NAME="${EXPORT_GROUP}_observations"

# We rely on the region-based table built in regional_base.sh:
#   <REGION_TAG>_min${MIN_OBS}_all_taxa_obs
# which is typically "NAfull_min50_all_taxa_obs", etc.
REGIONAL_TABLE="${REGION_TAG}_min${MIN_OBS}_all_taxa_obs"

# 2) The observation columns we'll select from the region table
#    (defined by get_obs_columns in functions.sh)
OBS_COLUMNS="$(get_obs_columns)"

# 3) Drop any old table if it exists
execute_sql "
DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;
"

# 4) Create new table by joining the region table to expanded_taxa
#    so that we skip any taxon_id not found in expanded_taxa (i.e., inactive or missing).
#    We also filter by e."taxonActive" = TRUE and the clade condition.
send_notification "Joining regional table ${REGIONAL_TABLE} to expanded_taxa"
print_progress "Joining regional table ${REGIONAL_TABLE} to expanded_taxa"

execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    ${OBS_COLUMNS},
    -- Include the base expanded_taxa columns (taxonID, rankLevel, name)
    e.\"taxonID\"       AS expanded_taxonID,
    e.\"rankLevel\"     AS expanded_rankLevel,
    e.\"name\"          AS expanded_name,

    -- Include all ancestral taxonID columns (sparsely populated, but required)
    e.\"L5_taxonID\",
    e.\"L10_taxonID\",
    e.\"L11_taxonID\",
    e.\"L12_taxonID\",
    e.\"L13_taxonID\",
    e.\"L15_taxonID\",
    e.\"L20_taxonID\",
    e.\"L24_taxonID\",
    e.\"L25_taxonID\",
    e.\"L26_taxonID\",
    e.\"L27_taxonID\",
    e.\"L30_taxonID\",
    e.\"L32_taxonID\",
    e.\"L33_taxonID\",
    e.\"L33_5_taxonID\",
    e.\"L34_taxonID\",
    e.\"L34_5_taxonID\",
    e.\"L35_taxonID\",
    e.\"L37_taxonID\",
    e.\"L40_taxonID\",
    e.\"L43_taxonID\",
    e.\"L44_taxonID\",
    e.\"L45_taxonID\",
    e.\"L47_taxonID\",
    e.\"L50_taxonID\",
    e.\"L53_taxonID\",
    e.\"L57_taxonID\",
    e.\"L60_taxonID\",
    e.\"L67_taxonID\",
    e.\"L70_taxonID\"

FROM \"${REGIONAL_TABLE}\" obs
JOIN \"expanded_taxa\" e
   ON e.\"taxonID\" = obs.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND ${CLADE_CONDITION};
"

# 5) Export to CSV (random subset w/ photos).
#    We must also select the same set of columns (plus the photo fields).
#    Notice we reference the newly created table "TABLE_NAME" for the final data.
send_notification "Exporting filtered observations"
print_progress "Exporting filtered observations"

if [ "${PRIMARY_ONLY}" = true ]; then
    # Photos with position=0, quality_grade='research'
    # CLARIFY: We assume ${EXPORT_DIR} is a valid path in the container. Please confirm.
    # ASSUMPTION: The container user has write access to ${EXPORT_DIR}.
    execute_sql "
COPY (
    SELECT
        o.*,
        o.expanded_taxonID,
        o.expanded_rankLevel,
        o.expanded_name,
        o.\"L5_taxonID\",
        o.\"L10_taxonID\",
        o.\"L11_taxonID\",
        o.\"L12_taxonID\",
        o.\"L13_taxonID\",
        o.\"L15_taxonID\",
        o.\"L20_taxonID\",
        o.\"L24_taxonID\",
        o.\"L25_taxonID\",
        o.\"L26_taxonID\",
        o.\"L27_taxonID\",
        o.\"L30_taxonID\",
        o.\"L32_taxonID\",
        o.\"L33_taxonID\",
        o.\"L33_5_taxonID\",
        o.\"L34_taxonID\",
        o.\"L34_5_taxonID\",
        o.\"L35_taxonID\",
        o.\"L37_taxonID\",
        o.\"L40_taxonID\",
        o.\"L43_taxonID\",
        o.\"L44_taxonID\",
        o.\"L45_taxonID\",
        o.\"L47_taxonID\",
        o.\"L50_taxonID\",
        o.\"L53_taxonID\",
        o.\"L57_taxonID\",
        o.\"L60_taxonID\",
        o.\"L67_taxonID\",
        o.\"L70_taxonID\",
        p.photo_uuid,
        p.photo_id,
        p.extension,
        p.license,
        p.width,
        p.height,
        p.position
    FROM \"${TABLE_NAME}\" o
    JOIN photos p
      ON o.observation_uuid = p.observation_uuid
    WHERE p.position = 0
      AND o.quality_grade = 'research'
    ORDER BY random()
    LIMIT ${MAX_RN}
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"
else
    # All photos for the final set, restricted to quality_grade='research'
    # CLARIFY: We assume ${EXPORT_DIR} is a valid path in the container. Please confirm.
    # ASSUMPTION: The container user has write access to ${EXPORT_DIR}.
    execute_sql "
COPY (
    SELECT
        o.*,
        o.expanded_taxonID,
        o.expanded_rankLevel,
        o.expanded_name,
        o.\"L5_taxonID\",
        o.\"L10_taxonID\",
        o.\"L11_taxonID\",
        o.\"L12_taxonID\",
        o.\"L13_taxonID\",
        o.\"L15_taxonID\",
        o.\"L20_taxonID\",
        o.\"L24_taxonID\",
        o.\"L25_taxonID\",
        o.\"L26_taxonID\",
        o.\"L27_taxonID\",
        o.\"L30_taxonID\",
        o.\"L32_taxonID\",
        o.\"L33_taxonID\",
        o.\"L33_5_taxonID\",
        o.\"L34_taxonID\",
        o.\"L34_5_taxonID\",
        o.\"L35_taxonID\",
        o.\"L37_taxonID\",
        o.\"L40_taxonID\",
        o.\"L43_taxonID\",
        o.\"L44_taxonID\",
        o.\"L45_taxonID\",
        o.\"L47_taxonID\",
        o.\"L50_taxonID\",
        o.\"L53_taxonID\",
        o.\"L57_taxonID\",
        o.\"L60_taxonID\",
        o.\"L67_taxonID\",
        o.\"L70_taxonID\",
        p.photo_uuid,
        p.photo_id,
        p.extension,
        p.license,
        p.width,
        p.height,
        p.position
    FROM \"${TABLE_NAME}\" o
    JOIN photos p
      ON o.observation_uuid = p.observation_uuid
    WHERE o.quality_grade = 'research'
    ORDER BY random()
    LIMIT ${MAX_RN}
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"
fi

# 6) Summarize exported data: how many observations, taxa, observers?
print_progress "Creating export statistics"
STATS=$(execute_sql "
WITH export_stats AS (
    SELECT 
        COUNT(DISTINCT observation_uuid) as num_observations,
        COUNT(DISTINCT taxon_id) as num_taxa,
        COUNT(DISTINCT observer_id) as num_observers
    FROM \"${TABLE_NAME}\"
)
SELECT format(
    'Exported Data Statistics:
    Observations: %s
    Unique Taxa: %s
    Unique Observers: %s',
    num_observations, num_taxa, num_observers
)
FROM export_stats;")

echo "${STATS}" >> "${HOST_EXPORT_DIR}/export_summary.txt"

print_progress "Cladistic filtering complete"