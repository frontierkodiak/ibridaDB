#!/bin/bash
# ------------------------------------------------------------------------------
# cladistic.sh (Revised for Option A: always quoted taxon-level columns)
# ------------------------------------------------------------------------------
# Creates a final observation subset for a user-specified clade/metaclade,
# referencing the "expanded_taxa" table. The input table for this script is
# typically provided in ANCESTORS_OBS_TABLE (set by regional_base.sh).
#
# Steps:
#   1) Validate environment & drop <EXPORT_GROUP>_observations if it exists
#   2) Construct a filtering WHERE clause for research/non-research quality
#   3) Create the <EXPORT_GROUP>_observations table by joining to expanded_taxa
#   4) Optionally wipe partial ranks (L20, L30, L40) if MIN_OCCURRENCES_PER_RANK is set
#   5) Export to CSV via partition-based random sampling
#
# Environment Variables (required):
#   ANCESTORS_OBS_TABLE
#   EXPORT_GROUP
#   DB_CONTAINER, DB_USER, DB_NAME, BASE_DIR, etc.
#
# Optional:
#   RG_FILTER_MODE, MIN_OCCURRENCES_PER_RANK, MAX_RN, PRIMARY_ONLY,
#   INCLUDE_ELEVATION_EXPORT
#
# Revision highlights:
#   - All references to columns like L5_taxonID, L10_taxonID, etc. are double-quoted
#     so that Postgres stores them in mixed-case and we can select them without
#     running into case-folding issues.
# ------------------------------------------------------------------------------

set -e

# 1) Source common functions & check ANCESTORS_OBS_TABLE
source "${BASE_DIR}/common/functions.sh"

if [ -z "${ANCESTORS_OBS_TABLE:-}" ]; then
  echo "ERROR: cladistic.sh requires ANCESTORS_OBS_TABLE to be set."
  exit 1
fi

print_progress "cladistic.sh: Using ancestor-based table = ${ANCESTORS_OBS_TABLE}"

TABLE_NAME="${EXPORT_GROUP}_observations"
execute_sql "DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;"

# ------------------------------------------------------------------------------
# 2) Construct RG filter condition & possibly rewrite "L10_taxonID"
# ------------------------------------------------------------------------------
rg_where_condition="TRUE"
rg_l10_col="e.\"L10_taxonID\""  # might become NULL::integer if we do a wipe

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
OBS_COLUMNS="$(get_obs_columns)"  # e.g. observation_uuid, observer_id, latitude, longitude, etc.

# We explicitly alias each expanded_taxa column in quotes, so that Postgres
# stores them in mixed-case (e.g. "L5_taxonID") and we can select them reliably.
EXPANDED_TAXA_COLS="
    e.\"taxonID\"        AS \"expanded_taxonID\",
    e.\"rankLevel\"      AS \"expanded_rankLevel\",
    e.\"name\"           AS \"expanded_name\",
    e.\"L5_taxonID\"     AS \"L5_taxonID\",
    ${rg_l10_col}        AS \"L10_taxonID\",
    e.\"L11_taxonID\"    AS \"L11_taxonID\",
    e.\"L12_taxonID\"    AS \"L12_taxonID\",
    e.\"L13_taxonID\"    AS \"L13_taxonID\",
    e.\"L15_taxonID\"    AS \"L15_taxonID\",
    e.\"L20_taxonID\"    AS \"L20_taxonID\",
    e.\"L24_taxonID\"    AS \"L24_taxonID\",
    e.\"L25_taxonID\"    AS \"L25_taxonID\",
    e.\"L26_taxonID\"    AS \"L26_taxonID\",
    e.\"L27_taxonID\"    AS \"L27_taxonID\",
    e.\"L30_taxonID\"    AS \"L30_taxonID\",
    e.\"L32_taxonID\"    AS \"L32_taxonID\",
    e.\"L33_taxonID\"    AS \"L33_taxonID\",
    e.\"L33_5_taxonID\"  AS \"L33_5_taxonID\",
    e.\"L34_taxonID\"    AS \"L34_taxonID\",
    e.\"L34_5_taxonID\"  AS \"L34_5_taxonID\",
    e.\"L35_taxonID\"    AS \"L35_taxonID\",
    e.\"L37_taxonID\"    AS \"L37_taxonID\",
    e.\"L40_taxonID\"    AS \"L40_taxonID\",
    e.\"L43_taxonID\"    AS \"L43_taxonID\",
    e.\"L44_taxonID\"    AS \"L44_taxonID\",
    e.\"L45_taxonID\"    AS \"L45_taxonID\",
    e.\"L47_taxonID\"    AS \"L47_taxonID\",
    e.\"L50_taxonID\"    AS \"L50_taxonID\",
    e.\"L53_taxonID\"    AS \"L53_taxonID\",
    e.\"L57_taxonID\"    AS \"L57_taxonID\",
    e.\"L60_taxonID\"    AS \"L60_taxonID\",
    e.\"L67_taxonID\"    AS \"L67_taxonID\",
    e.\"L70_taxonID\"    AS \"L70_taxonID\"
"

execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    ${OBS_COLUMNS},        -- these are unquoted columns like observation_uuid, etc.
    o.in_region,           -- already all-lowercase
    ${EXPANDED_TAXA_COLS}
FROM \"${ANCESTORS_OBS_TABLE}\" o
JOIN expanded_taxa e ON e.\"taxonID\" = o.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND (${rg_where_condition});
"

# ------------------------------------------------------------------------------
# 4) Optional partial-rank wipe for L20, L30, L40
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
# 5) Export Final CSV with partition-based sampling for research-grade species
# ------------------------------------------------------------------------------
print_progress "cladistic.sh: Exporting final CSV with partition-based sampling"

pos_condition="TRUE"
if [ "${PRIMARY_ONLY:-false}" = "true" ]; then
  pos_condition="p.position=0"
fi

# Build the final column list for the CSV, all double-quoted so that the
# headers appear exactly as L5_taxonID, etc., in the CSV.
#
# We'll re-use get_obs_columns() output but wrap them in quotes for final usage.
# Then we manually append in_region, expanded columns, etc., all in quotes.

quote_columns() {
  # Helper that takes a comma-delimited string of column names and
  # returns them as a quoted, comma-delimited list (e.g. "colA","colB",...).
  local input="$1"
  local quoted=""
  IFS=',' read -ra cols <<< "$input"
  for col in "${cols[@]}"; do
    col="$(echo "$col" | xargs)"  # trim spaces
    [ -n "$quoted" ] && quoted="$quoted, \"$col\"" || quoted="\"$col\""
  done
  echo "$quoted"
}

RAW_OBS_COLS="$(get_obs_columns)"  # e.g. observation_uuid, observer_id, ...
QUOTED_OBS_COLS="$(quote_columns "$RAW_OBS_COLS")"

# Now define the expanded columns in quotes. Note that these match the aliases
# we used above (AS "L5_taxonID", etc.). Also in_region is a lowercase column,
# but we quote it for consistency in the final CSV.
CSV_OBS_COLS="$QUOTED_OBS_COLS,
\"in_region\",
\"expanded_taxonID\",
\"expanded_rankLevel\",
\"expanded_name\",
\"L5_taxonID\",
\"L10_taxonID\",
\"L11_taxonID\",
\"L12_taxonID\",
\"L13_taxonID\",
\"L15_taxonID\",
\"L20_taxonID\",
\"L24_taxonID\",
\"L25_taxonID\",
\"L26_taxonID\",
\"L27_taxonID\",
\"L30_taxonID\",
\"L32_taxonID\",
\"L33_taxonID\",
\"L33_5_taxonID\",
\"L34_taxonID\",
\"L34_5_taxonID\",
\"L35_taxonID\",
\"L37_taxonID\",
\"L40_taxonID\",
\"L43_taxonID\",
\"L44_taxonID\",
\"L45_taxonID\",
\"L47_taxonID\",
\"L50_taxonID\",
\"L53_taxonID\",
\"L57_taxonID\",
\"L60_taxonID\",
\"L67_taxonID\",
\"L70_taxonID\""

# Photo columns, also quoted
CSV_PHOTO_COLS="\"photo_uuid\", \"photo_id\", \"extension\", \"license\", \"width\", \"height\", \"position\""

# Debug logging: use quote_literal() to avoid array-literal syntax errors
debug_sql_obs="
SELECT 'DEBUG: Final CSV obs columns => ' ||
       quote_literal('${CSV_OBS_COLS}');
"
debug_sql_photo="
SELECT 'DEBUG: Final CSV photo columns => ' ||
       quote_literal('${CSV_PHOTO_COLS}');
"

execute_sql "$debug_sql_obs"
execute_sql "$debug_sql_photo"

# If no MAX_RN, default to 3000
if [ -z "${MAX_RN:-}" ]; then
  echo "Warning: MAX_RN not set, defaulting to 3000"
  MAX_RN=3000
fi

EXPORT_FILE="${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv"

# Final COPY query uses these columns in quotes
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
        PARTITION BY o.\"L10_taxonID\"  -- This is a quoted column in the new table
        ORDER BY
          CASE WHEN o.in_region THEN 0 ELSE 1 END,
          random()
      ) AS rn
    FROM \"${TABLE_NAME}\" o
    JOIN photos p ON o.observation_uuid = p.observation_uuid
    WHERE ${pos_condition}
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
    WHERE ${pos_condition}
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
) TO '${EXPORT_FILE}'
  WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"

print_progress "cladistic.sh: CSV export complete"
print_progress "Exported final CSV to ${EXPORT_FILE}"
