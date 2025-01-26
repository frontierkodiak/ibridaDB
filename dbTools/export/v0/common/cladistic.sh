#!/bin/bash
# -------------------------------------------------------------------------------
# cladistic.sh
# -------------------------------------------------------------------------------
# Creates a final observation subset for a specified clade/metaclade,
# referencing the "expanded_taxa" table in an ancestor-aware manner.
#
# Main Steps:
#   1) Load relevant environment variables (CLADE, METACLADE, etc.)
#   2) Join the ancestor-based table (<REGION_TAG>_min${MIN_OBS}_sp_and_ancestors_obs)
#   3) Apply RG_FILTER_MODE (including optional wiping of species-level IDs if requested)
#   4) (Optional) Partial-rank wiping (MIN_OCCURRENCES_PER_RANK) for L20, L30, and L40
#   5) Export final CSV with union-based approach (research species vs. everything else)
#
# NOTE:
#  - The final summary stats are handled by main.sh.
#  - If MIN_OCCURRENCES_PER_RANK is unset or == -1, we skip the partial-rank wiping step.
#  - We only wipe L20, L30, and L40 to keep performance manageable (and preserve class-level ranks).
#  - If future expansions require more ranks, the logic below can be extended easily.

source "${BASE_DIR}/common/functions.sh"
source "${BASE_DIR}/common/clade_defns.sh"

CLADE_CONDITION="$(get_clade_condition)"
print_progress "Creating filtered tables for ${EXPORT_GROUP}"

# -------------------------------------------------------------------------------
# 0) Table references and columns
# -------------------------------------------------------------------------------
ANCESTOR_BASE_TABLE="${REGION_TAG}_min${MIN_OBS}_sp_and_ancestors_obs"
TABLE_NAME="${EXPORT_GROUP}_observations"
OBS_COLUMNS="$(get_obs_columns)"

# -------------------------------------------------------------------------------
# Step A) Drop any old table
# -------------------------------------------------------------------------------
execute_sql "
DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;
"

send_notification "Joining table ${ANCESTOR_BASE_TABLE} to expanded_taxa"
print_progress "Joining table ${ANCESTOR_BASE_TABLE} to expanded_taxa"

# -------------------------------------------------------------------------------
# Step B) Construct WHERE clause & column rewriting based on RG_FILTER_MODE
# -------------------------------------------------------------------------------
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

# -------------------------------------------------------------------------------
# Step C) Create final table <EXPORT_GROUP>_observations
# -------------------------------------------------------------------------------
execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    ${OBS_COLUMNS},
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
FROM \"${ANCESTOR_BASE_TABLE}\" o
JOIN \"expanded_taxa\" e ON e.\"taxonID\" = o.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND ${CLADE_CONDITION}
  AND (${rg_where_condition});
"

# -------------------------------------------------------------------------------
# Step D) (Optional) Partial-rank wiping for L20, L30, L40
#    - If MIN_OCCURRENCES_PER_RANK is empty or == -1, skip wiping.
#    - If set >= 1, we compute usage for L20_taxonID, L30_taxonID, and L40_taxonID
#      and nullify them if usage < MIN_OCCURRENCES_PER_RANK.
# -------------------------------------------------------------------------------
if [ -z "${MIN_OCCURRENCES_PER_RANK}" ] || [ "${MIN_OCCURRENCES_PER_RANK}" = "-1" ]; then
  print_progress "Skipping partial-rank wipe (MIN_OCCURRENCES_PER_RANK not set or == -1)."
else
  print_progress "Applying partial-rank wipe with threshold = ${MIN_OCCURRENCES_PER_RANK}"

  # We only do this for major ranks L20, L30, L40. This helps performance
  # and is the specified requirement that we do not handle minor ranks or class (L50).
  RANK_COLS=("L20_taxonID" "L30_taxonID" "L40_taxonID")

  for rc in "${RANK_COLS[@]}"; do
    print_progress "Wiping low-occurrence ${rc} if usage < ${MIN_OCCURRENCES_PER_RANK}"

    # Implementation approach: compute usage counts, then update
    # We'll do it in a single statement for each rc:
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
# Step E) Export final CSV with union of research-limited vs. everything else
# -------------------------------------------------------------------------------
send_notification "Exporting filtered observations"
print_progress "Exporting filtered observations"

pos_condition="TRUE"
if [ "${PRIMARY_ONLY}" = true ]; then
    pos_condition="p.position=0"
fi

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
      o.*,
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
  SELECT * FROM capped_research_species
  WHERE rn <= ${MAX_RN}
  UNION ALL
  SELECT * FROM everything_else
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"

print_progress "Cladistic filtering complete"
