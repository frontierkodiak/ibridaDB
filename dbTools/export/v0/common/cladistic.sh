#!/bin/bash
# -------------------------------------------------------------------------------
# cladistic.sh
# -------------------------------------------------------------------------------
# Creates a final observation subset for the user-specified clade/metaclade,
# referencing the "expanded_taxa" table. The input table for this script is
# typically provided in ANCESTORS_OBS_TABLE, which contains:
#
#   - All observations of species that passed the MIN_OBS threshold in the
#     specified region (REGION_TAG bounding box) plus all their ancestral
#     taxonIDs, up to the root rank(s) of the chosen CLADE/METACLADE.
#
#   - If INCLUDE_OUT_OF_REGION_OBS=true, that table may also include
#     observations that fall outside the bounding box but belong to those
#     same species or ancestor taxonIDs. Otherwise, the bounding box is
#     re-applied to keep only in-bounds data.
#
#   - If INCLUDE_MINOR_RANKS_IN_ANCESTORS=false, the table only includes
#     major (decade) ranks up to the boundary. If =true, minor ranks are
#     included.
#
#   - This table is named like:
#       ${REGION_TAG}_min${MIN_OBS}_sp_and_ancestors_obs_${CLADE_ID}_${RANK_MODE}
#     but we do NOT compute that name here. Instead, we read the environment
#     variable $ANCESTORS_OBS_TABLE, which is set by regional_base.sh.
#
# Once we have that ancestor-based observation set, we:
#   1) Create an export-specific table named <EXPORT_GROUP>_observations.
#   2) Possibly filter out or rewrite certain rows based on RG_FILTER_MODE
#      (e.g. wiping species-level IDs if not research grade).
#   3) (Optional) Wipe partial ranks (L20, L30, L40) if they have fewer than
#      MIN_OCCURRENCES_PER_RANK occurrences.
#   4) Export the final dataset to CSV, applying a maximum row limit per
#      species (MAX_RN) for research-grade rows, and unioning that with
#      everything else.
#
# Environment Variables Used:
#   - ANCESTORS_OBS_TABLE: The table containing the region/clade-specific
#                          ancestor-based observations. (Set by regional_base.sh)
#   - EXPORT_GROUP:        Used as a prefix for the final table name
#   - RG_FILTER_MODE:      Determines how we handle non-research vs. research rows
#   - MIN_OCCURRENCES_PER_RANK: If set >= 1, triggers partial-rank wiping for L20/L30/L40
#   - MAX_RN:              The maximum number of random research-grade rows to keep
#   - PRIMARY_ONLY:        If true, we only keep photo records where position=0
#   - EXPORT_DIR:          Destination for the CSV export
#   - DB_CONTAINER, DB_USER, DB_NAME, etc. for database connections
#
# -------------------------------------------------------------------------------
set -e

source "${BASE_DIR}/common/functions.sh"
source "${BASE_DIR}/common/clade_defns.sh"  # only needed if we reference get_clade_condition, etc.

# -------------------------------------------------------------------------------
# 0) Validate that ANCESTORS_OBS_TABLE is set
# -------------------------------------------------------------------------------
if [ -z "${ANCESTORS_OBS_TABLE}" ]; then
  echo "ERROR: cladistic.sh requires ANCESTORS_OBS_TABLE to be set (exported by regional_base.sh)."
  exit 1
fi

print_progress "cladistic.sh: Using ancestor-based table = ${ANCESTORS_OBS_TABLE}"

# We'll build a final table named <EXPORT_GROUP>_observations
TABLE_NAME="${EXPORT_GROUP}_observations"
OBS_COLUMNS="$(get_obs_columns)"

# -------------------------------------------------------------------------------
# Step A) Drop any old final table
# -------------------------------------------------------------------------------
execute_sql "
DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;
"

# -------------------------------------------------------------------------------
# Step B) Construct a WHERE clause & rewriting logic based on RG_FILTER_MODE
# -------------------------------------------------------------------------------
# Typically, we interpret RG_FILTER_MODE to decide how to handle research vs. non-research
# observations. Possibly we wipe the L10_taxonID for non-research, or exclude them, etc.

rg_where_condition="TRUE"
rg_l10_col="e.\"L10_taxonID\""

case "${RG_FILTER_MODE}" in
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

print_progress "Building final table \"${TABLE_NAME}\" from ${ANCESTORS_OBS_TABLE}"

# -------------------------------------------------------------------------------
# Step C) Create <EXPORT_GROUP>_observations table by joining to expanded_taxa
# -------------------------------------------------------------------------------
# In theory, ${ANCESTORS_OBS_TABLE} has taxon_id referencing the desired region/clade
# observations. We join with expanded_taxa for additional columns. Then we apply
# RG_FILTER_MODE logic.

execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    o.${OBS_COLUMNS},
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
FROM \"${ANCESTORS_OBS_TABLE}\" o
JOIN expanded_taxa e ON e.\"taxonID\" = o.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND (${rg_where_condition});
"

# -------------------------------------------------------------------------------
# Step D) Optional Partial-Rank Wiping (L20, L30, L40) if MIN_OCCURRENCES_PER_RANK >= 1
# -------------------------------------------------------------------------------
if [ -z "${MIN_OCCURRENCES_PER_RANK}" ] || [ "${MIN_OCCURRENCES_PER_RANK}" = "-1" ]; then
  print_progress "Skipping partial-rank wipe (MIN_OCCURRENCES_PER_RANK not set or == -1)."
else
  print_progress "Applying partial-rank wipe with threshold = ${MIN_OCCURRENCES_PER_RANK}"

  RANK_COLS=("L20_taxonID" "L30_taxonID" "L40_taxonID")
  for rc in "${RANK_COLS[@]}"; do
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

# -------------------------------------------------------------------------------
# Step E) Export Final CSV with a max row limit per species for research-grade
# -------------------------------------------------------------------------------
send_notification "cladistic.sh: Exporting filtered observations"
print_progress "cladistic.sh: Exporting filtered observations (Step E)"

pos_condition="TRUE"
if [ "${PRIMARY_ONLY}" = true ]; then
    pos_condition="p.position=0"
fi

# ------------------------------------------------------------------------------
# 1) Let's define a list of columns from the <EXPORT_GROUP>_observations table
#    that we want in our final CSV. We'll call them "obs_columns_for_union".
#    We'll also add the photo columns explicitly.
# ------------------------------------------------------------------------------
obs_columns_for_union="
    observation_uuid,
    observer_id,
    latitude,
    longitude,
    positional_accuracy,
    taxon_id,
    quality_grade,
    observed_on,
    anomaly_score,
    expanded_taxonID,
    expanded_rankLevel,
    expanded_name,
    L5_taxonID,
    L10_taxonID,
    L11_taxonID,
    L12_taxonID,
    L13_taxonID,
    L15_taxonID,
    L20_taxonID,
    L24_taxonID,
    L25_taxonID,
    L26_taxonID,
    L27_taxonID,
    L30_taxonID,
    L32_taxonID,
    L33_taxonID,
    L33_5_taxonID,
    L34_taxonID,
    L34_5_taxonID,
    L35_taxonID,
    L37_taxonID,
    L40_taxonID,
    L43_taxonID,
    L44_taxonID,
    L45_taxonID,
    L47_taxonID,
    L50_taxonID,
    L53_taxonID,
    L57_taxonID,
    L60_taxonID,
    L67_taxonID,
    L70_taxonID
"

# We also want photo columns in the final CSV:
photo_columns_for_union="
    photo_uuid,
    photo_id,
    extension,
    license,
    width,
    height,
    position
"

# ------------------------------------------------------------------------------
# 2) We'll do the subselect for "capped_research_species", selecting ALL above
#    columns + an internal row_number() as 'rn'. We'll *not* include 'rn' in the
#    final union, so we'll put that in a subselect.
# ------------------------------------------------------------------------------
debug_columns_capped="
SELECT 'DEBUG: capped_research_species columns => ' ||
       array_to_string(array[
         '$(echo $obs_columns_for_union | xargs)',
         '$(echo $photo_columns_for_union | xargs)',
         'rn'
       ], ', ')
 AS debug_cols;
"

debug_columns_everything="
SELECT 'DEBUG: everything_else columns => ' ||
       array_to_string(array[
         '$(echo $obs_columns_for_union | xargs)',
         '$(echo $photo_columns_for_union | xargs)'
       ], ', ')
 AS debug_cols;
"

execute_sql "$debug_columns_capped"
execute_sql "$debug_columns_everything"

execute_sql "
COPY (
  WITH
    capped_research_species AS (
      SELECT
        -- 1. The observation columns
        o.observation_uuid,
        o.observer_id,
        o.latitude,
        o.longitude,
        o.positional_accuracy,
        o.taxon_id,
        o.quality_grade,
        o.observed_on,
        o.anomaly_score,
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

        -- 2. Photo columns
        p.photo_uuid,
        p.photo_id,
        p.extension,
        p.license,
        p.width,
        p.height,
        p.position,

        -- 3. row_number for limiting research-grade
        ROW_NUMBER() OVER (
          PARTITION BY o.\"L10_taxonID\"
          ORDER BY random()
        ) AS rn

      FROM \"${TABLE_NAME}\" o
      JOIN photos p ON o.observation_uuid = p.observation_uuid
      WHERE
        ${pos_condition}
        AND o.quality_grade='research'
        AND o.\"L10_taxonID\" IS NOT NULL
    ),

    everything_else AS (
      SELECT
        -- exact same columns, but no row_number
        o.observation_uuid,
        o.observer_id,
        o.latitude,
        o.longitude,
        o.positional_accuracy,
        o.taxon_id,
        o.quality_grade,
        o.observed_on,
        o.anomaly_score,
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
      JOIN photos p ON o.observation_uuid = p.observation_uuid
      WHERE
        ${pos_condition}
        AND NOT (o.quality_grade='research' AND o.\"L10_taxonID\" IS NOT NULL)
    )

  -- ----------------------------------------------------------------------------
  -- Now build the final union, but for the first subselect, we only want
  -- rows where 'rn' <= ${MAX_RN}. Note that we do NOT select 'rn' in the union columns.
  -- ----------------------------------------------------------------------------
  SELECT
    observation_uuid,
    observer_id,
    latitude,
    longitude,
    positional_accuracy,
    taxon_id,
    quality_grade,
    observed_on,
    anomaly_score,
    expanded_taxonID,
    expanded_rankLevel,
    expanded_name,
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
    \"L70_taxonID\",
    photo_uuid,
    photo_id,
    extension,
    license,
    width,
    height,
    position
  FROM capped_research_species
  WHERE rn <= ${MAX_RN}

  UNION ALL

  SELECT
    observation_uuid,
    observer_id,
    latitude,
    longitude,
    positional_accuracy,
    taxon_id,
    quality_grade,
    observed_on,
    anomaly_score,
    expanded_taxonID,
    expanded_rankLevel,
    expanded_name,
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
    \"L70_taxonID\",
    photo_uuid,
    photo_id,
    extension,
    license,
    width,
    height,
    position
  FROM everything_else
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"

print_progress "cladistic.sh: Finished exporting observations CSV (Step E complete)"
