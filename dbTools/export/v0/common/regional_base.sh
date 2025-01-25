#!/bin/bash
# --------------------------------------------------------------------------------
# regional_base.sh
# --------------------------------------------------------------------------------
# This script creates two tables for a given region (REGION_TAG) and MIN_OBS:
#   1) <REGION_TAG>_min${MIN_OBS}_all_taxa:
#      The set of species (rank_level=10) that have at least MIN_OBS
#      research-grade observations within the bounding box.
#
#   2) <REGION_TAG>_min${MIN_OBS}_all_taxa_obs:
#      All observations whose taxon_id is in (1). If INCLUDE_OUT_OF_REGION_OBS=true,
#      we do NOT re-apply the bounding-box filter, so out-of-region observations
#      are included. If false, we restrict again by bounding box.
#
# This is a partial step toward the "ancestor-aware" approach. For now, we only
# pick species that pass the threshold, ignoring higher or lower ranks.
#
# Usage:
#   - Sourced by main.sh
#   - Relies on environment variables:
#       REGION_TAG, MIN_OBS, INCLUDE_OUT_OF_REGION_OBS
#       DB_CONTAINER, DB_USER, DB_NAME, etc.
#
# CHANGES:
#   * Removed debug_counts table creation to streamline performance.
#   * No changes to final summary; that is now unified in main.sh.
# --------------------------------------------------------------------------------

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

# 1) Set region coordinates
set_region_coordinates

print_progress "Dropping existing tables"
execute_sql "
DROP TABLE IF EXISTS \"${REGION_TAG}_min${MIN_OBS}_all_taxa\" CASCADE;
DROP TABLE IF EXISTS \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\" CASCADE;
"

# --------------------------------------------------
# Removed debug_counts block:
#   print_progress "Creating debug_counts for region ${REGION_TAG}"
#   ...
# --------------------------------------------------

# 2) Create <REGION_TAG>_min${MIN_OBS}_all_taxa
#    We only include species (rank_level=10) that have >= MIN_OBS
#    research-grade obs in region.
print_progress "Creating table \"${REGION_TAG}_min${MIN_OBS}_all_taxa\""
execute_sql "
CREATE TABLE \"${REGION_TAG}_min${MIN_OBS}_all_taxa\" AS
SELECT s.taxon_id
FROM observations s
JOIN taxa t ON t.taxon_id = s.taxon_id
WHERE t.rank_level = 10
  AND s.quality_grade = 'research'
  AND s.geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326)
GROUP BY s.taxon_id
HAVING COUNT(s.observation_uuid) >= ${MIN_OBS};
"

# 3) Create <REGION_TAG>_min${MIN_OBS}_all_taxa_obs
#    If INCLUDE_OUT_OF_REGION_OBS=true, we do not filter again by bounding box.
#    Otherwise, we re-check s.geom against the region.
print_progress "Creating table \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\""
OBS_COLUMNS=$(get_obs_columns)
echo "Using columns: ${OBS_COLUMNS}"

if [ "${INCLUDE_OUT_OF_REGION_OBS}" = "true" ]; then
    execute_sql "
    CREATE TABLE \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
        SELECT taxon_id
        FROM \"${REGION_TAG}_min${MIN_OBS}_all_taxa\"
    );
    "
else
    execute_sql "
    CREATE TABLE \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
        SELECT taxon_id
        FROM \"${REGION_TAG}_min${MIN_OBS}_all_taxa\"
    )
    AND geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326);
    "
fi

print_progress "Regional base tables created"