#!/bin/bash
# ------------------------------------------------------------------------------
# regional_base.sh
# ------------------------------------------------------------------------------
# Generates region-specific species tables and associated ancestor sets,
# factoring in the user's clade/metaclade and the major/minor rank mode.
#
# Steps:
#   1) Parse environment variables and region coordinates.
#   2) Build or reuse the <REGION_TAG>_min<MIN_OBS>_all_sp table (region + MIN_OBS only).
#   3) Parse clade condition (single or multi-root). If multi-root, check overlap.
#   4) Build or reuse <REGION_TAG>_min<MIN_OBS>_all_sp_and_ancestors_<cladeID>_<mode>
#   5) Build or reuse <REGION_TAG>_min<MIN_OBS>_sp_and_ancestors_obs_<cladeID>_<mode>
#   6) Output final info/summary
#
# Requires:
#   - environment variables: DB_NAME, DB_CONTAINER, DB_USER, ...
#   - script variables: REGION_TAG, MIN_OBS, SKIP_REGIONAL_BASE,
#     INCLUDE_OUT_OF_REGION_OBS, INCLUDE_MINOR_RANKS_IN_ANCESTORS,
#     etc.
#
# ------------------------------------------------------------------------------

source "${BASE_DIR}/common/functions.sh"
source "${BASE_DIR}/common/clade_defns.sh"
source "${BASE_DIR}/common/clade_helpers.sh"
source "${BASE_DIR}/common/region_defns.sh"

# ---------------------------------------------------------------------------
# 0) Validate Environment + Setup
# ---------------------------------------------------------------------------
: "${REGION_TAG:?Error: REGION_TAG is not set}"
: "${MIN_OBS:?Error: MIN_OBS is not set}"
: "${SKIP_REGIONAL_BASE:?Error: SKIP_REGIONAL_BASE is not set}"
: "${INCLUDE_OUT_OF_REGION_OBS:?Error: INCLUDE_OUT_OF_REGION_OBS is not set}"
: "${INCLUDE_MINOR_RANKS_IN_ANCESTORS:?Error: INCLUDE_MINOR_RANKS_IN_ANCESTORS is not set}"

print_progress "=== regional_base.sh: Starting Ancestor-Aware Regional Base Generation ==="

# Retrieve bounding box for the region
get_region_coordinates || {
  echo "Failed to retrieve bounding box for REGION_TAG=${REGION_TAG}" >&2
  exit 1
}

print_progress "Using bounding box => XMIN=${XMIN}, YMIN=${YMIN}, XMAX=${XMAX}, YMAX=${YMAX}"

# ---------------------------------------------------------------------------
# 1) Build or Reuse <REGION_TAG>_min<MIN_OBS>_all_sp
# ---------------------------------------------------------------------------
ALL_SP_TABLE="${REGION_TAG}_min${MIN_OBS}_all_sp"

check_and_build_all_sp() {
  # Check existence
  local table_exists
  table_exists="$(execute_sql "
    SELECT 1 FROM pg_catalog.pg_tables
    WHERE schemaname='public'
      AND tablename='${ALL_SP_TABLE}'
    LIMIT 1;
  ")"

  if [[ "${table_exists}" =~ 1 ]]; then
    # If table exists, check row count
    local row_count
    row_count="$(execute_sql "
      SELECT count(*) FROM \"${ALL_SP_TABLE}\";
    ")"
    local numeric_count
    numeric_count="$(echo "${row_count}" | awk '/[0-9]/{print $1}' | head -1)"

    if [[ -n "${numeric_count}" && "${numeric_count}" -gt 0 ]]; then
      print_progress "Table ${ALL_SP_TABLE} exists with ${numeric_count} rows"
      if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
        print_progress "SKIP_REGIONAL_BASE=true => reusing existing _all_sp table"
        return 0
      else
        print_progress "Not skipping => dropping and recreating"
      fi
    fi
  fi

  print_progress "Creating (or recreating) table \"${ALL_SP_TABLE}\""
  execute_sql "DROP TABLE IF EXISTS \"${ALL_SP_TABLE}\" CASCADE;"

  # Build the table with bounding box + rank_level=10 + MIN_OBS filter
  execute_sql "
  CREATE TABLE \"${ALL_SP_TABLE}\" AS
  SELECT s.taxon_id
  FROM observations s
  JOIN taxa t ON t.taxon_id = s.taxon_id
  WHERE t.rank_level = 10
    AND s.quality_grade = 'research'
    AND s.geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326)
  GROUP BY s.taxon_id
  HAVING COUNT(s.observation_uuid) >= ${MIN_OBS};
  "
}

check_and_build_all_sp

# ---------------------------------------------------------------------------
# 2) Parse Clade Condition & Check Overlap if Multi-root
# ---------------------------------------------------------------------------
CLADE_CONDITION="$(get_clade_condition)"
print_progress "Clade Condition: ${CLADE_CONDITION}"

root_list=( $(parse_clade_expression "${CLADE_CONDITION}") )
root_count="${#root_list[@]}"
print_progress "Found ${root_count} root(s) from the clade condition"

# Decide on a short ID for the clade/metaclade
# (if you want to embed actual environment variables: e.g. $CLADE or $METACLADE
#  or parse the user-supplied string from the condition. We'll do a naive approach.)
if [ -n "${METACLADE}" ]; then
  CLADE_ID="${METACLADE}"
elif [ -n "${CLADE}" ]; then
  CLADE_ID="${CLADE}"
elif [ -n "${MACROCLADE}" ]; then
  CLADE_ID="${MACROCLADE}"
else
  # fallback if user didn't set anything
  CLADE_ID="universal"
fi

# Clean up the clade_id so it doesn't contain spaces or special chars
CLADE_ID="${CLADE_ID// /_}"

# If multi-root => check overlap
if [ "${root_count}" -gt 1 ]; then
  print_progress "Multiple roots => checking independence"
  check_root_independence "${DB_NAME}" "${root_list[@]}"
  if [ $? -ne 0 ]; then
    echo "ERROR: Overlap detected among metaclade roots. Aborting."
    exit 1
  fi
  print_progress "All roots are mutually independent"
fi

# Decide majorOrMinor string
if [ "${INCLUDE_MINOR_RANKS_IN_ANCESTORS}" = "true" ]; then
  RANK_MODE="inclMinor"
else
  RANK_MODE="majorOnly"
fi

# Build final table names
ANCESTORS_TABLE="${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors_${CLADE_ID}_${RANK_MODE}"
ANCESTORS_OBS_TABLE="${REGION_TAG}_min${MIN_OBS}_sp_and_ancestors_obs_${CLADE_ID}_${RANK_MODE}"

# ---------------------------------------------------------------------------
# 3) Build or Reuse <REGION_TAG>_min<MIN_OBS>_all_sp_and_ancestors_<cladeID>_<mode>
# ---------------------------------------------------------------------------
check_and_build_ancestors() {
  # 1) Check if the table already exists and skip if user wants SKIP_REGIONAL_BASE
  local table_exists
  table_exists="$(execute_sql "
    SELECT 1 FROM pg_catalog.pg_tables
    WHERE schemaname='public'
      AND tablename='${ANCESTORS_TABLE}'
    LIMIT 1;
  ")"

  if [[ "${table_exists}" =~ 1 ]]; then
    local row_count
    row_count="$(execute_sql "
      SELECT count(*) FROM \"${ANCESTORS_TABLE}\";
    ")"
    local numeric_count
    numeric_count="$(echo "${row_count}" | awk '/[0-9]/{print $1}' | head -1)"

    if [[ -n "${numeric_count}" && "${numeric_count}" -gt 0 ]]; then
      print_progress "Table ${ANCESTORS_TABLE} exists with ${numeric_count} rows"
      if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
        print_progress "Skipping creation of ancestors table"
        return 0
      else
        print_progress "Not skipping => dropping and recreating"
      fi
    fi
  fi

  print_progress "Creating table \"${ANCESTORS_TABLE}\""
  execute_sql "DROP TABLE IF EXISTS \"${ANCESTORS_TABLE}\" CASCADE;"
  execute_sql "
  CREATE TABLE \"${ANCESTORS_TABLE}\" (
    taxon_id integer PRIMARY KEY
  );
  "

  # ---------------------------------------------------------------------------
  # insert_ancestors_for_root():
  #
  # For a given single root (rank_part=50, root_taxid=47158, etc.),
  # we gather all species from <ALL_SP_TABLE> that have e.L50_taxonID=47158,
  # then unroll their ancestors via CROSS JOIN LATERAL on the columns L5..L70,
  # look up each ancestor's rankLevel from expanded_taxa, and keep only those
  # with rankLevel < boundary_rank. Insert them into ANCESTORS_TABLE.
  # ---------------------------------------------------------------------------
  local insert_ancestors_for_root
  insert_ancestors_for_root() {
    local root_pair="$1"  # e.g. "50=47158"
    local rank_part="${root_pair%%=*}"
    local root_taxid="${root_pair##*=}"

    local col_name="L${rank_part}_taxonID"

    # Decide boundary (majorOnly vs. inclMinor)
    local boundary_rank="$rank_part"
    if [ "${INCLUDE_MINOR_RANKS_IN_ANCESTORS}" = "false" ]; then
      boundary_rank="$(get_major_rank_floor "${rank_part}")"
    fi

    execute_sql "
    ----------------------------------------------------------------
    -- 1) Gather species from <ALL_SP_TABLE> that belong to this root
    ----------------------------------------------------------------
    DROP TABLE IF EXISTS temp_${root_taxid}_sp_list CASCADE;
    CREATE TEMP TABLE temp_${root_taxid}_sp_list AS
    SELECT s.taxon_id
    FROM \"${ALL_SP_TABLE}\" s
    JOIN expanded_taxa e ON e.\"taxonID\" = s.taxon_id
    WHERE e.\"${col_name}\" = ${root_taxid};

    ----------------------------------------------------------------
    -- 2) Unroll each species's ancestor IDs (L5..L70) and filter by rank
    ----------------------------------------------------------------
    DROP TABLE IF EXISTS temp_${root_taxid}_all_ancestors CASCADE;

    WITH unravel AS (
      -- 'unravel' yields each row's potential ancestor columns
      SELECT
        e.\"taxonID\"        AS sp_id,
        e.\"L5_taxonID\"     AS L5_id,
        e.\"L10_taxonID\"    AS L10_id,
        e.\"L11_taxonID\"    AS L11_id,
        e.\"L12_taxonID\"    AS L12_id,
        e.\"L13_taxonID\"    AS L13_id,
        e.\"L15_taxonID\"    AS L15_id,
        e.\"L20_taxonID\"    AS L20_id,
        e.\"L24_taxonID\"    AS L24_id,
        e.\"L25_taxonID\"    AS L25_id,
        e.\"L26_taxonID\"    AS L26_id,
        e.\"L27_taxonID\"    AS L27_id,
        e.\"L30_taxonID\"    AS L30_id,
        e.\"L32_taxonID\"    AS L32_id,
        e.\"L33_taxonID\"    AS L33_id,
        e.\"L33_5_taxonID\"  AS L33_5_id,
        e.\"L34_taxonID\"    AS L34_id,
        e.\"L34_5_taxonID\"  AS L34_5_id,
        e.\"L35_taxonID\"    AS L35_id,
        e.\"L37_taxonID\"    AS L37_id,
        e.\"L40_taxonID\"    AS L40_id,
        e.\"L43_taxonID\"    AS L43_id,
        e.\"L44_taxonID\"    AS L44_id,
        e.\"L45_taxonID\"    AS L45_id,
        e.\"L47_taxonID\"    AS L47_id,
        e.\"L50_taxonID\"    AS L50_id,
        e.\"L53_taxonID\"    AS L53_id,
        e.\"L57_taxonID\"    AS L57_id,
        e.\"L60_taxonID\"    AS L60_id,
        e.\"L67_taxonID\"    AS L67_id,
        e.\"L70_taxonID\"    AS L70_id
      FROM expanded_taxa e
      JOIN temp_${root_taxid}_sp_list sp
         ON e.\"taxonID\" = sp.taxon_id
    ),
    all_ancestors AS (
      -- We'll produce rows for the species' own ID (sp_id)
      -- plus each potential ancestor ID, then filter by rankLevel < boundary_rank.
      SELECT sp_id AS taxon_id
      FROM unravel

      UNION ALL

      SELECT x.\"taxonID\" AS taxon_id
      FROM unravel u
      CROSS JOIN LATERAL (VALUES
        (u.L5_id),(u.L10_id),(u.L11_id),(u.L12_id),(u.L13_id),(u.L15_id),
        (u.L20_id),(u.L24_id),(u.L25_id),(u.L26_id),(u.L27_id),(u.L30_id),
        (u.L32_id),(u.L33_id),(u.L33_5_id),(u.L34_id),(u.L34_5_id),(u.L35_id),
        (u.L37_id),(u.L40_id),(u.L43_id),(u.L44_id),(u.L45_id),(u.L47_id),
        (u.L50_id),(u.L53_id),(u.L57_id),(u.L60_id),(u.L67_id),(u.L70_id)
      ) anc(ancestor_id)
      JOIN expanded_taxa x ON x.\"taxonID\" = anc.ancestor_id
      WHERE x.\"rankLevel\" < ${boundary_rank}
    )
    SELECT DISTINCT taxon_id
    INTO TEMP temp_${root_taxid}_all_ancestors
    FROM all_ancestors
    WHERE taxon_id IS NOT NULL;

    ----------------------------------------------------------------
    -- 3) Insert into the final ancestors table
    ----------------------------------------------------------------
    INSERT INTO \"${ANCESTORS_TABLE}\"(taxon_id)
    SELECT DISTINCT taxon_id
    FROM temp_${root_taxid}_all_ancestors;
    "
  }

  # Decide single vs. multi-root
  if [ "${root_count}" -eq 0 ]; then
    print_progress "No recognized root => no ancestors inserted. (Might be 'TRUE' clade?)"
  elif [ "${root_count}" -eq 1 ]; then
    print_progress "Single root => straightforward insertion"
    insert_ancestors_for_root "${root_list[0]}"
  else
    print_progress "Multi-root => union each root's ancestor set"
    for root_entry in "${root_list[@]}"; do
      insert_ancestors_for_root "${root_entry}"
    done
  fi
}

check_and_build_ancestors

# ---------------------------------------------------------------------------
# 4) Build or Reuse <REGION_TAG>_min<MIN_OBS>_sp_and_ancestors_obs_<cladeID>_<mode>
# ---------------------------------------------------------------------------
check_and_build_ancestors_obs() {
  local table_exists
  table_exists="$(execute_sql "
    SELECT 1 FROM pg_catalog.pg_tables
    WHERE schemaname='public'
      AND tablename='${ANCESTORS_OBS_TABLE}'
    LIMIT 1;
  ")"

  if [[ "${table_exists}" =~ 1 ]]; then
    local row_count
    row_count="$(execute_sql "
      SELECT count(*) FROM \"${ANCESTORS_OBS_TABLE}\";
    ")"
    local numeric_count
    numeric_count="$(echo "${row_count}" | awk '/[0-9]/{print $1}' | head -1)"

    if [[ -n "${numeric_count}" && "${numeric_count}" -gt 0 ]]; then
      print_progress "Table ${ANCESTORS_OBS_TABLE} exists with ${numeric_count} rows"
      if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
        print_progress "Skipping creation of ancestors_obs table"
        return 0
      else
        print_progress "Not skipping => dropping and recreating"
      fi
    fi
  fi

  print_progress "Creating table \"${ANCESTORS_OBS_TABLE}\""
  execute_sql "DROP TABLE IF EXISTS \"${ANCESTORS_OBS_TABLE}\" CASCADE;"

  local OBS_COLUMNS
  OBS_COLUMNS="$(get_obs_columns)"

  if [ "${INCLUDE_OUT_OF_REGION_OBS}" = "true" ]; then
    execute_sql "
    CREATE TABLE \"${ANCESTORS_OBS_TABLE}\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
      SELECT taxon_id
      FROM \"${ANCESTORS_TABLE}\"
    );
    "
  else
    execute_sql "
    CREATE TABLE \"${ANCESTORS_OBS_TABLE}\" AS
    SELECT ${OBS_COLUMNS}
    FROM observations
    WHERE taxon_id IN (
      SELECT taxon_id
      FROM \"${ANCESTORS_TABLE}\"
    )
    AND geom && ST_MakeEnvelope(${XMIN}, ${YMIN}, ${XMAX}, ${YMAX}, 4326);
    "
  fi
}

check_and_build_ancestors_obs

export ANCESTORS_OBS_TABLE="${ANCESTORS_OBS_TABLE}" # for cladistic.sh

print_progress "=== regional_base.sh: Completed building base tables for ${REGION_TAG}, minObs=${MIN_OBS}, clade=${CLADE_ID}, mode=${RANK_MODE} ==="
