#!/bin/bash
# ------------------------------------------------------------------------------
# cladistic.sh
# ------------------------------------------------------------------------------
# Creates a final observation subset for a user-specified clade/metaclade,
# referencing the "expanded_taxa" table. The input table for this script is
# typically provided in ANCESTORS_OBS_TABLE (set by regional_base.sh). This
# table contains:
#   - All observations of species that passed the MIN_OBS threshold
#     in the specified region bounding box, plus all their ancestral
#     taxonIDs, up to the chosen root rank(s).
#   - If INCLUDE_OUT_OF_REGION_OBS=true, out-of-region rows for those
#     same species are also included (with in_region=false).
#   - If INCLUDE_MINOR_RANKS_IN_ANCESTORS=false, only major decade ranks
#     are included; otherwise, minor ranks are included.
#
# Steps in cladistic.sh:
#   1) Validate environment & drop any pre-existing final table <EXPORT_GROUP>_observations
#   2) Construct a filtering WHERE clause for research/non-research quality using RG_FILTER_MODE
#   3) Create the final <EXPORT_GROUP>_observations table by joining to expanded_taxa
#   4) Optionally wipe partial ranks (L20, L30, L40) if MIN_OCCURRENCES_PER_RANK is set
#   5) Export to CSV via a partition-based random sampling approach:
#       - "capped_research_species" subquery for each species' research-grade rows
#       - "everything_else" subquery for all other rows
#       - Union them, writing to <EXPORT_GROUP>_photos.csv
#   6) Print progress messages, handle debug logs for column lists
#
# Environment Variables:
#   ANCESTORS_OBS_TABLE -> Name of the region/clade-based observations table
#   EXPORT_GROUP        -> Suffix for the final table name & CSV
#   RG_FILTER_MODE      -> One of: [ONLY_RESEARCH, ALL, ALL_EXCLUDE_SPECIES_NON_RESEARCH, etc.]
#   MIN_OCCURRENCES_PER_RANK -> If >= 1, triggers partial-rank wiping for L20/L30/L40
#   MAX_RN             -> Max research-grade rows per species
#   PRIMARY_ONLY        -> If true, only photos with position=0 are included
#   INCLUDE_ELEVATION_EXPORT -> If true & release != r0, includes 'elevation_meters'
#
#   DB_CONTAINER, DB_USER, DB_NAME, BASE_DIR, etc. must also be set.
#
# NOTE: Because we have thoroughly documented the final columns in docs/schemas.md,
# we now rely on get_obs_columns() for the main observation columns, appending
# the expanded_taxa columns and photo columns carefully to preserve the final layout.
# ------------------------------------------------------------------------------

set -e

# 1) Source common functions & validate ANCESTORS_OBS_TABLE
source "${BASE_DIR}/common/functions.sh"

if [ -z "${ANCESTORS_OBS_TABLE:-}" ]; then
  echo "ERROR: cladistic.sh requires ANCESTORS_OBS_TABLE to be set."
  exit 1
fi

print_progress "cladistic.sh: Using ancestor-based table = ${ANCESTORS_OBS_TABLE}"

TABLE_NAME="${EXPORT_GROUP}_observations"
execute_sql "DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;"

# ------------------------------------------------------------------------------
# 2) Construct RG filter condition & possibly rewrite L10_taxonID if wiping
# ------------------------------------------------------------------------------
rg_where_condition="TRUE"
rg_l10_col="e.\"L10_taxonID\""

case "${RG_FILTER_MODE:-ALL}" in
  "ONLY_RESEARCH")
    rg_where_condition="o.quality_grade='research'"
    ;;
  "ALL")
    rg_where_condition="TRUE"
    ;;
  "ALL_EXCLUDE_SPECIES_NON_RESEARCH")
    rg_where_condition="NOT (o.quality_grade!='research' AND e.\"L10_taxonID\" IS NOT NULL)"
    ;;
  "ONLY_NONRESEARCH")
    rg_where_condition="o.quality_grade!='research'"
    ;;
  "ONLY_NONRESEARCH_EXCLUDE_SPECIES")
    rg_where_condition="(o.quality_grade!='research' AND e.\"L10_taxonID\" IS NULL)"
    ;;
  "ONLY_NONRESEARCH_WIPE_SPECIES_LABEL")
    rg_where_condition="o.quality_grade!='research'"
    rg_l10_col="NULL::integer"
    ;;
  *)
    rg_where_condition="TRUE"
    ;;
esac

# ------------------------------------------------------------------------------
# 3) Create <EXPORT_GROUP>_observations by joining ANCESTORS_OBS_TABLE + expanded_taxa
# ------------------------------------------------------------------------------
# Observations columns come from get_obs_columns(), which includes optional
# elevation_meters & anomaly_score if present in this release.
OBS_COLUMNS="$(get_obs_columns)"

# We'll define the expanded_taxa columns we need:
EXPANDED_TAXA_COLS="
    e.\"taxonID\"       AS expanded_taxonID,
    e.\"rankLevel\"     AS expanded_rankLevel,
    e.\"name\"          AS expanded_name,
    e.\"L5_taxonID\",
    ${rg_l10_col}       AS \"L10_taxonID\",
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
"

# Join & filter
execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    ${OBS_COLUMNS},
    o.in_region,
    ${EXPANDED_TAXA_COLS}
FROM \"${ANCESTORS_OBS_TABLE}\" o
JOIN expanded_taxa e ON e.\"taxonID\" = o.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND (${rg_where_condition});
"

# ------------------------------------------------------------------------------
# 4) (Optional) Partial-Rank Wiping for L20, L30, L40
# ------------------------------------------------------------------------------
if [ -z "${MIN_OCCURRENCES_PER_RANK:-}" ] || [ "${MIN_OCCURRENCES_PER_RANK}" = "-1" ]; then
  print_progress "Skipping partial-rank wipe (MIN_OCCURRENCES_PER_RANK not set or -1)."
else
  print_progress "Applying partial-rank wipe with threshold = ${MIN_OCCURRENCES_PER_RANK}"

  for rc in L20_taxonID L30_taxonID L40_taxonID; do
    print_progress "Wiping low-occurrence ${rc} if usage < ${MIN_OCCURRENCES_PER_RANK}"
    execute_sql "
    WITH usage_ct AS (
      SELECT \"${rc}\" as tid, COUNT(*) as c
      FROM \"${TABLE_NAME}\"
      WHERE \"${rc}\" IS NOT NULL
      GROUP BY 1
    )
    UPDATE \"${TABLE_NAME}\"
    SET \"${rc}\" = NULL
    FROM usage_ct
    WHERE usage_ct.tid = \"${TABLE_NAME}\".\"${rc}\"
      AND usage_ct.c < ${MIN_OCCURRENCES_PER_RANK};
    "
  done
fi

# ------------------------------------------------------------------------------
# 5) Export Final CSV using partition-based sampling for research-grade species
# ------------------------------------------------------------------------------
print_progress "cladistic.sh: Exporting final CSV with partition-based sampling"

# We'll define a photo filter to include only position=0 if PRIMARY_ONLY=true
pos_condition="TRUE"
if [ "${PRIMARY_ONLY:-false}" = "true" ]; then
  pos_condition="p.position=0"
fi

# For clarity, let's define the final set of columns in our CSV union
# We'll re-use get_obs_columns for the observation portion, and re-list
# the expanded & photo columns to keep final control. Then we add 'rn'.
CSV_OBS_COLS="$(get_obs_columns), in_region,
expanded_taxonID, expanded_rankLevel, expanded_name,
L5_taxonID, L10_taxonID, L11_taxonID, L12_taxonID, L13_taxonID, L15_taxonID,
L20_taxonID, L24_taxonID, L25_taxonID, L26_taxonID, L27_taxonID,
L30_taxonID, L32_taxonID, L33_taxonID, L33_5_taxonID, L34_taxonID, L34_5_taxonID,
L35_taxonID, L37_taxonID, L40_taxonID, L43_taxonID, L44_taxonID, L45_taxonID,
L47_taxonID, L50_taxonID, L53_taxonID, L57_taxonID, L60_taxonID, L67_taxonID, L70_taxonID
"

# Photo columns
CSV_PHOTO_COLS="photo_uuid, photo_id, extension, license, width, height, position"

# We'll use debug queries to log these column lists:
debug_sql_obs="
SELECT 'DEBUG: Final CSV obs columns => ' ||
       array_to_string(array['$(echo $CSV_OBS_COLS | xargs)'], ', ');
"
debug_sql_photo="
SELECT 'DEBUG: Final CSV photo columns => ' ||
       array_to_string(array['$(echo $CSV_PHOTO_COLS | xargs)'], ', ');
"

execute_sql "$debug_sql_obs"
execute_sql "$debug_sql_photo"

# If MAX_RN is not set, default to 3000
if [ -z "${MAX_RN:-}" ]; then
  echo "Warning: MAX_RN not set, defaulting to 3000"
  MAX_RN=3000
fi

# Now produce the CSV with two subqueries:
#   1) capped_research_species -> research-grade, species-level rows, partition-limited
#   2) everything_else -> non-research or non-species-level
EXPORT_FILE="${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv"

execute_sql "
COPY (
  WITH
  capped_research_species AS (
    SELECT
      o.*,
      p.photo_uuid,
      p.photo_id,
      p.extension,
      p.license,
      p.width,
      p.height,
      p.position,
      ROW_NUMBER() OVER (
        PARTITION BY o.\"L10_taxonID\"
        ORDER BY
          CASE WHEN o.in_region THEN 0 ELSE 1 END,
          random()
      ) AS rn
    FROM \"${TABLE_NAME}\" o
    JOIN photos p ON o.observation_uuid = p.observation_uuid
    WHERE $pos_condition
      AND o.quality_grade='research'
      AND o.\"L10_taxonID\" IS NOT NULL
  ),
  everything_else AS (
    SELECT
      o.*,
      p.photo_uuid,
      p.photo_id,
      p.extension,
      p.license,
      p.width,
      p.height,
      p.position,
      NULL::bigint AS rn
    FROM \"${TABLE_NAME}\" o
    JOIN photos p ON o.observation_uuid = p.observation_uuid
    WHERE $pos_condition
      AND NOT (o.quality_grade='research' AND o.\"L10_taxonID\" IS NOT NULL)
  )
  SELECT
    ${CSV_OBS_COLS},
    ${CSV_PHOTO_COLS},
    rn
  FROM capped_research_species
  WHERE rn <= ${MAX_RN}

  UNION ALL

  SELECT
    ${CSV_OBS_COLS},
    ${CSV_PHOTO_COLS},
    rn
  FROM everything_else
) TO '${EXPORT_FILE}' WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"

print_progress "cladistic.sh: CSV export complete"
print_progress "Exported final CSV to ${EXPORT_FILE}"
