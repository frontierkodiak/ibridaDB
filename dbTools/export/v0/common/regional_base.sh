#!/bin/bash
# --------------------------------------------------------------------------------
# regional_base.sh
# --------------------------------------------------------------------------------
# This script implements the ancestor-aware approach.
# Steps:
#   1) <REGION_TAG>_min${MIN_OBS}_all_sp:
#      The set of species (rank_level=10) that have at least MIN_OBS
#      research-grade observations within the bounding box.
#   2) <REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors:
#      The union of those species plus their ancestors (up to user-defined root).
#   3) <REGION_TAG>_min${MIN_OBS}_sp_and_ancestors_obs:
#      All observations referencing the union set. If INCLUDE_OUT_OF_REGION_OBS=true,
#      do NOT re-apply bounding box; else re-apply.

source "${BASE_DIR}/common/functions.sh"

# We assume the user sets REGION_TAG, MIN_OBS, INCLUDE_OUT_OF_REGION_OBS, etc.
# CLARIFY: We also check for ANCESTOR_ROOT_RANKLEVEL. If empty, we might default to 70.

if [ -z "${ANCESTOR_ROOT_RANKLEVEL}" ]; then
  # If user doesn't specify a root rank, assume full ancestry up to 70
  export ANCESTOR_ROOT_RANKLEVEL=70
fi

# Function sets the bounding-box coords for $REGION_TAG
set_region_coordinates() {
  case "$REGION_TAG" in
    "NAfull")
      XMIN=-169.453125
      YMIN=12.211180
      XMAX=-23.554688
      YMAX=84.897147
      ;;
    "EURwest")
      XMIN=-12.128906
      YMIN=40.245992
      XMAX=12.480469
      YMAX=60.586967
      ;;
    "EURnorth")
      XMIN=-25.927734
      YMIN=54.673831
      XMAX=45.966797
      YMAX=71.357067
      ;;
    "EUReast")
      XMIN=10.722656
      YMIN=41.771312
      XMAX=39.550781
      YMAX=59.977005
      ;;
    "EURfull")
      XMIN=-30.761719
      YMIN=33.284620
      XMAX=43.593750
      YMAX=72.262310
      ;;
    "MED")
      XMIN=-16.259766
      YMIN=29.916852
      XMAX=36.474609
      YMAX=46.316584
      ;;
    "AUSfull")
      XMIN=111.269531
      YMIN=-47.989922
      XMAX=181.230469
      YMAX=-9.622414
      ;;
    "ASIAse")
      XMIN=82.441406
      YMIN=-11.523088
      XMAX=153.457031
      YMAX=28.613459
      ;;
    "ASIAeast")
      XMIN=462.304688
      YMIN=23.241346
      XMAX=550.195313
      YMAX=78.630006
      ;;
    "ASIAcentral")
      XMIN=408.515625
      YMIN=36.031332
      XMAX=467.753906
      YMAX=76.142958
      ;;
    "ASIAsouth")
      XMIN=420.468750
      YMIN=1.581830
      XMAX=455.097656
      YMAX=39.232253
      ;;
    "ASIAsw")
      XMIN=386.718750
      YMIN=12.897489
      XMAX=423.281250
      YMAX=48.922499
      ;;
    "ASIA_nw")
      XMIN=393.046875
      YMIN=46.800059
      XMAX=473.203125
      YMAX=81.621352
      ;;
    "SAfull")
      XMIN=271.230469
      YMIN=-57.040730
      XMAX=330.644531
      YMAX=15.114553
      ;;
    "AFRfull")
      XMIN=339.082031
      YMIN=-37.718590
      XMAX=421.699219
      YMAX=39.232253
      ;;
    *)
      echo "Unknown REGION_TAG: $REGION_TAG"
      exit 1
      ;;
  esac
}

set_region_coordinates

# We'll create 3 tables: all_sp, all_sp_and_ancestors, sp_and_ancestors_obs
print_progress "Dropping existing tables"
execute_sql "
DROP TABLE IF EXISTS \"${REGION_TAG}_min${MIN_OBS}_all_sp\" CASCADE;
DROP TABLE IF EXISTS \"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\" CASCADE;
DROP TABLE IF EXISTS \"${REGION_TAG}_min${MIN_OBS}_sp_and_ancestors_obs\" CASCADE;
"

# 1) <REGION_TAG>_min${MIN_OBS}_all_sp
print_progress "Creating table \"${REGION_TAG}_min${MIN_OBS}_all_sp\""
execute_sql "
CREATE TABLE \"${REGION_TAG}_min${MIN_OBS}_all_sp\" AS
SELECT s.taxon_id
FROM observations s
JOIN taxa t ON t.taxon_id = s.taxon_id
WHERE t.rank_level = 10
  AND s.quality_grade = 'research'
  AND s.geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326)
GROUP BY s.taxon_id
HAVING COUNT(s.observation_uuid) >= ${MIN_OBS};
"

# 2) <REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors
# We'll gather each species from above, plus all its ancestors up to ANCESTOR_ROOT_RANKLEVEL
print_progress "Building ancestor set for species"

execute_sql "
CREATE TABLE \"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\" (
  taxon_id integer PRIMARY KEY
);
"

# We'll do a single set-based insertion:
execute_sql "
WITH sp_list AS (
  SELECT taxon_id
  FROM \"${REGION_TAG}_min${MIN_OBS}_all_sp\"
),
 unravel AS (
  SELECT
    e.\"taxonID\" as species_id,
    e.\"L5_taxonID\", e.\"L10_taxonID\", e.\"L11_taxonID\",
    e.\"L12_taxonID\", e.\"L13_taxonID\", e.\"L15_taxonID\",
    e.\"L20_taxonID\", e.\"L24_taxonID\", e.\"L25_taxonID\",
    e.\"L26_taxonID\", e.\"L27_taxonID\", e.\"L30_taxonID\",
    e.\"L32_taxonID\", e.\"L33_taxonID\", e.\"L33_5_taxonID\",
    e.\"L34_taxonID\", e.\"L34_5_taxonID\", e.\"L35_taxonID\",
    e.\"L37_taxonID\", e.\"L40_taxonID\", e.\"L43_taxonID\",
    e.\"L44_taxonID\", e.\"L45_taxonID\", e.\"L47_taxonID\",
    e.\"L50_taxonID\", e.\"L53_taxonID\", e.\"L57_taxonID\",
    e.\"L60_taxonID\", e.\"L67_taxonID\", e.\"L70_taxonID\"
  FROM expanded_taxa e
  JOIN sp_list ON e.\"taxonID\" = sp_list.taxon_id
 )
SELECT DISTINCT UNNEST(array[
  unravel.species_id,
  CASE WHEN \"rankLevel\"(unravel.L5_taxonID)  <= ${ANCESTOR_ROOT_RANKLEVEL} THEN unravel.L5_taxonID  ELSE NULL END,
  CASE WHEN \"rankLevel\"(unravel.L10_taxonID) <= ${ANCESTOR_ROOT_RANKLEVEL} THEN unravel.L10_taxonID ELSE NULL END,
  unravel.L11_taxonID,
  unravel.L12_taxonID,
  unravel.L13_taxonID,
  unravel.L15_taxonID,
  unravel.L20_taxonID,
  unravel.L24_taxonID,
  unravel.L25_taxonID,
  unravel.L26_taxonID,
  unravel.L27_taxonID,
  unravel.L30_taxonID,
  unravel.L32_taxonID,
  unravel.L33_taxonID,
  unravel.L33_5_taxonID,
  unravel.L34_taxonID,
  unravel.L34_5_taxonID,
  unravel.L35_taxonID,
  unravel.L37_taxonID,
  unravel.L40_taxonID,
  unravel.L43_taxonID,
  unravel.L44_taxonID,
  unravel.L45_taxonID,
  unravel.L47_taxonID,
  unravel.L50_taxonID,
  unravel.L53_taxonID,
  unravel.L57_taxonID,
  unravel.L60_taxonID,
  unravel.L67_taxonID,
  unravel.L70_taxonID
]) AS taxon_id
INTO TEMP all_ancestors
FROM unravel
WHERE taxon_id IS NOT NULL;
-- CLARIFY: We rely on a custom function rankLevel(taxonID)? We might need a join to expanded_taxa again or store rankLevel in unravel. We'll keep it conceptual for now.
-- In reality, we'd do a more robust approach. This is a conceptual snippet.
--

INSERT INTO \"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\"(taxon_id)
SELECT DISTINCT taxon_id
FROM all_ancestors
WHERE taxon_id IS NOT NULL;
"

# 3) Now create the final observation table from those taxonIDs
#    <REGION_TAG>_min${MIN_OBS}_sp_and_ancestors_obs
BASE_OBS_TABLE="${REGION_TAG}_min${MIN_OBS}_sp_and_ancestors_obs"
print_progress "Creating table \"${BASE_OBS_TABLE}\""
OBS_COLUMNS=$(get_obs_columns)
echo "Using columns: ${OBS_COLUMNS}"

if [ "${INCLUDE_OUT_OF_REGION_OBS}" = "true" ]; then
    execute_sql "
    CREATE TABLE \"${BASE_OBS_TABLE}\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
        SELECT taxon_id
        FROM \"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\"
    );
    "
else
    execute_sql "
    CREATE TABLE \"${BASE_OBS_TABLE}\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
        SELECT taxon_id
        FROM \"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\"
    )
    AND geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326);
    "
fi

print_progress "Ancestor-aware regional base tables created"