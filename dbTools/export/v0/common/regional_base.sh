#!/bin/bash

# Note: functions are sourced from main.sh

# Function to set region-specific coordinates
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


# Set region coordinates
set_region_coordinates

# # Debug: Check version and release values
# print_progress "Debugging database parameters"
# execute_sql "
# SELECT DISTINCT version, release, count(*)
# FROM observations
# GROUP BY version, release;"

# # Debug: Check coordinate bounds
# print_progress "Checking observations within coordinate bounds"
# execute_sql "
# SELECT COUNT(*)
# FROM observations
# WHERE latitude BETWEEN ${YMIN} AND ${YMAX}
# AND longitude BETWEEN ${XMIN} AND ${XMAX};"

# # Debug: Check quality grade distribution
# print_progress "Checking quality grade distribution"
# execute_sql "
# SELECT quality_grade, COUNT(*)
# FROM observations
# WHERE version = '${VERSION_VALUE}'
# AND release = '${RELEASE_VALUE}'
# GROUP BY quality_grade;"

# Drop existing tables if they exist
print_progress "Dropping existing tables"
execute_sql "DROP TABLE IF EXISTS ${REGION_TAG}_min${MIN_OBS}_all_taxa CASCADE;"
execute_sql "DROP TABLE IF EXISTS ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs CASCADE;"

# Create table with debug output
print_progress "Creating table ${REGION_TAG}_min${MIN_OBS}_all_taxa with debug"
execute_sql "
CREATE TABLE ${REGION_TAG}_min${MIN_OBS}_all_taxa AS
WITH debug_counts AS (
    SELECT COUNT(*) as total_obs,
           COUNT(DISTINCT taxon_id) as unique_taxa
    FROM observations
    WHERE
    -- TEMPORARY HOTFIX: Commenting out version filters until bulk update is complete
    -- version = '${VERSION_VALUE}'
    -- AND release = '${RELEASE_VALUE}'
    -- AND 
    geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326)
)
SELECT * FROM debug_counts;

SELECT DISTINCT observations.taxon_id
FROM observations
JOIN taxa ON observations.taxon_id = taxa.taxon_id
WHERE 
    -- TEMPORARY HOTFIX: Commenting out version filters until bulk update is complete
    -- observations.version = '${VERSION_VALUE}'
    -- AND observations.release = '${RELEASE_VALUE}'
    -- AND 
    NOT (taxa.rank_level = 10 AND observations.quality_grade != 'research')
    AND geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326)
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        WHERE 
        -- TEMPORARY HOTFIX: Commenting out version filters until bulk update is complete
        -- version = '${VERSION_VALUE}'
        -- AND release = '${RELEASE_VALUE}'
        -- AND 
        1=1
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= ${MIN_OBS}
    );

# Create table <REGION_TAG>_min<MIN_OBS>_all_taxa_obs with dynamic columns
print_progress "Creating table ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs"
OBS_COLUMNS=$(get_obs_columns)

# Debug: show the columns being used
echo "Using columns: ${OBS_COLUMNS}"

execute_sql "
CREATE TABLE ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs AS
SELECT ${OBS_COLUMNS}
FROM observations
WHERE 
    -- TEMPORARY HOTFIX: Commenting out version filters until bulk update is complete
    -- version = '${VERSION_VALUE}'
    -- AND release = '${RELEASE_VALUE}'
    -- AND 
    taxon_id IN (
        SELECT taxon_id
        FROM ${REGION_TAG}_min${MIN_OBS}_all_taxa
    );"

print_progress "Regional base tables created"