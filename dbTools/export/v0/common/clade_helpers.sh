#!/bin/bash
# ------------------------------------------------------------------------------
# clade_helpers.sh
# ------------------------------------------------------------------------------
# This file contains helper functions for multi-root/metaclade logic,
# rank boundary calculations, and advanced taxon-ancestry checks.
#
# Proposed usage:
#   1) "parse_clade_expression()" to parse user-provided condition strings
#      (e.g. "L50_taxonID=123 OR L40_taxonID=9999") into structured data.
#   2) "check_root_independence()" to verify that each root is truly disjoint
#      (none is an ancestor of another).
#   3) "get_major_rank_floor()" to compute the next-lower major-rank boundary
#      if user does not want to include minor ranks. Typically used if the root
#      is e.g. 57 => 50. If user includes minor ranks, we skip the rounding.
#
# NOTE: We do not forcibly integrate with existing "get_clade_condition()"
# in clade_defns.sh. Instead, you can call parse_clade_expression() if you
# want to do deeper multi-root logic.
#
# Implementation details:
#   - We store a reference map from "L<number>_taxonID" to the numeric rank
#     (e.g. "L50_taxonID" => 50). If the user requests minor ranks, we do not
#     round them down to the multiple of 10.
#   - We rely on "expanded_taxa" for ancestry checks. The "check_root_independence()"
#     function is conceptual: it gathers each root's entire ancestry (e.g. ~30
#     columns from L5..L70) and ensures no overlap among root sets.
#
# ------------------------------------------------------------------------------
#
# Exports:
#   - parse_clade_expression()
#   - check_root_independence()
#   - get_major_rank_floor()
#

# -------------------------------------------------------------
# A) Internal reference: Maps "L50_taxonID" => 50, "L40_taxonID" => 40, etc.
# -------------------------------------------------------------
declare -A RANKLEVEL_MAP=(
  ["L5_taxonID"]="5"
  ["L10_taxonID"]="10"
  ["L11_taxonID"]="11"
  ["L12_taxonID"]="12"
  ["L13_taxonID"]="13"
  ["L15_taxonID"]="15"
  ["L20_taxonID"]="20"
  ["L24_taxonID"]="24"
  ["L25_taxonID"]="25"
  ["L26_taxonID"]="26"
  ["L27_taxonID"]="27"
  ["L30_taxonID"]="30"
  ["L32_taxonID"]="32"
  ["L33_taxonID"]="33"
  ["L33_5_taxonID"]="33.5"
  ["L34_taxonID"]="34"
  ["L34_5_taxonID"]="34.5"
  ["L35_taxonID"]="35"
  ["L37_taxonID"]="37"
  ["L40_taxonID"]="40"
  ["L43_taxonID"]="43"
  ["L44_taxonID"]="44"
  ["L45_taxonID"]="45"
  ["L47_taxonID"]="47"
  ["L50_taxonID"]="50"
  ["L53_taxonID"]="53"
  ["L57_taxonID"]="57"
  ["L60_taxonID"]="60"
  ["L67_taxonID"]="67"
  ["L70_taxonID"]="70"
  # stateofmatter => 100, if we had that in expanded_taxa
)

# --------------------------------------------------------------------------
# parse_clade_expression()
# --------------------------------------------------------------------------
# Parses a SQL-like expression containing L{XX}_taxonID conditions into an array 
# of "rank=taxonID" pairs.
#
# Expected usage:
#   - We typically pass the result of get_clade_condition(), which looks like:
#     ("L50_taxonID" = 47158 OR "L50_taxonID" = 47119)
#   - The caller captures the results in an array:
#     roots=( $(parse_clade_expression "$clade_condition") )
#
# Processing steps:
#   1) Removes parentheses and double quotes
#   2) Splits on " OR " to handle multiple conditions
#   3) For each condition:
#      - Splits on '=' to get the LHS and RHS
#      - Extracts the rank number from L{XX}_taxonID pattern
#      - Pairs the rank with the taxonID
#
# Return format:
#   Space-separated strings in the form "rank=taxonID", e.g.:
#   "50=47158" "50=47119"
#
# Examples:
#   Input:  "L50_taxonID" = 47158
#   Output: 50=47158
#
#   Input:  ("L50_taxonID" = 47158 OR "L40_taxonID" = 9999)
#   Output: 50=47158 40=9999
#
# Notes:
#   - Case-insensitive: l50_taxonid and L50_taxonID are equivalent
#   - Spaces around '=' are optional
#   - Ignores any conditions not matching L{XX}_taxonID pattern
#   - Requires numeric taxonID values
# --------------------------------------------------------------------------
function parse_clade_expression() {
  local expr="$1"

  # 1) Remove parentheses and double quotes
  local cleaned_expr
  cleaned_expr="$(echo "$expr" | tr -d '()"')"
  echo "DEBUG [2]: After removing parentheses/quotes: '$cleaned_expr'" >&2

  # 2) Split on " OR " properly using sed
  local or_parts
  or_parts="$(echo "$cleaned_expr" | sed 's/ OR /\n/g')"
  
  local results=()
  
  while IFS= read -r part; do
    # Trim spaces and split on =
    local lhs rhs
    IFS='=' read -r lhs rhs <<< "$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    # Remove any remaining spaces
    lhs="$(echo "$lhs" | sed 's/[[:space:]]//g')"
    rhs="$(echo "$rhs" | sed 's/[[:space:]]//g')"
    
    # Extract the numeric part from LXX_taxonID
    if [[ $lhs =~ L([0-9]+)_taxonID ]]; then
      local rank="${BASH_REMATCH[1]}"
      results+=( "${rank}=${rhs}" )
    fi
  done <<< "$or_parts"

  echo "${results[@]}"
}

function check_root_independence() {
  # --------------------------------------------------------------------------
  # check_root_independence()
  #
  # PURPOSE:
  #   Ensures that each root in a multi-root scenario is truly independent,
  #   i.e., no root is an ancestor or descendant of another when viewed at
  #   or below the highest rank boundary. For example, if you have two roots
  #   at rank=50 (Insecta, Arachnida), they do share a phylum at rank=60
  #   (Arthropoda), but that is above their rank boundary, so it should NOT
  #   trigger a conflict.
  #
  # IMPLEMENTATION STEPS:
  #   1) Parse the root array (each item = "rank=taxonID", e.g. "50=47158").
  #   2) Find the globalMaxRank = max(r_i for each root).
  #   3) For each root, fetch its single row from expanded_taxa (which includes
  #      columns L5..L70). Then cross-join or left-join each potential ancestor
  #      ID to get that ancestor's rankLevel from expanded_taxa.
  #      Keep only those whose rankLevel <= globalMaxRank.
  #   4) Build a set of taxonIDs for that root (space-separated).
  #   5) Compare each pair of root sets for intersection. If they share a taxonID
  #      that is rankLevel <= globalMaxRank, we treat it as an overlap => return 1.
  #
  #   If no overlap is found among the rank <= globalMaxRank ancestors, return 0.
  #
  # USAGE:
  #   check_root_independence <db_name> <rootArray...>
  #   e.g. check_root_independence "myDB" "50=47158" "50=47119"
  #
  # RETURNS:
  #   0 if no overlap found, 1 if overlap is detected or root is not found.
  # --------------------------------------------------------------------------

  local dbName="$1"
  shift
  local roots=("$@")  # e.g. ("50=47158" "50=47119")

  # If there's 0 or 1 root, there's nothing to compare => trivially independent
  if [ "${#roots[@]}" -le 1 ]; then
    return 0
  fi

  # 1) Determine the global max rank among all root definitions
  local globalMaxRank=0
  for r in "${roots[@]}"; do
    local rr="${r%%=*}"
    if (( rr > globalMaxRank )); then
      globalMaxRank="$rr"
    fi
  done

  declare -A rootSets  # will map index => "list of ancestor taxonIDs"

  for i in "${!roots[@]}"; do
    local pair="${roots[$i]}"
    local rank="${pair%%=*}"
    local tid="${pair##*=}"

    # We'll do an expanded cross-lateral approach to gather the root's entire
    # L5..L70 columns, then retrieve each ancestor's rankLevel, ignoring any
    # with rankLevel > globalMaxRank.
    #
    # Because we only do ONE row for the root (plus ~30 columns), a single
    # CROSS JOIN to expanded_taxa for each ancestor ID is feasible.

    local sql="
COPY (
  WITH one_root AS (
    SELECT
      e.\"taxonID\" AS sp_id,
      e.\"L5_taxonID\", e.\"L10_taxonID\", e.\"L11_taxonID\", e.\"L12_taxonID\",
      e.\"L13_taxonID\", e.\"L15_taxonID\", e.\"L20_taxonID\", e.\"L24_taxonID\",
      e.\"L25_taxonID\", e.\"L26_taxonID\", e.\"L27_taxonID\", e.\"L30_taxonID\",
      e.\"L32_taxonID\", e.\"L33_taxonID\", e.\"L33_5_taxonID\", e.\"L34_taxonID\",
      e.\"L34_5_taxonID\", e.\"L35_taxonID\", e.\"L37_taxonID\", e.\"L40_taxonID\",
      e.\"L43_taxonID\", e.\"L44_taxonID\", e.\"L45_taxonID\", e.\"L47_taxonID\",
      e.\"L50_taxonID\", e.\"L53_taxonID\", e.\"L57_taxonID\", e.\"L60_taxonID\",
      e.\"L67_taxonID\", e.\"L70_taxonID\"
    FROM expanded_taxa e
    WHERE e.\"taxonID\" = ${tid}
  ),
  potential_ancestors AS (
    SELECT sp_id as taxon_id FROM one_root
    UNION ALL
    SELECT anc.\"taxonID\"
    FROM one_root o
    CROSS JOIN LATERAL (VALUES
      (o.\"L5_taxonID\"),(o.\"L10_taxonID\"),(o.\"L11_taxonID\"),(o.\"L12_taxonID\"),
      (o.\"L13_taxonID\"),(o.\"L15_taxonID\"),(o.\"L20_taxonID\"),(o.\"L24_taxonID\"),
      (o.\"L25_taxonID\"),(o.\"L26_taxonID\"),(o.\"L27_taxonID\"),(o.\"L30_taxonID\"),
      (o.\"L32_taxonID\"),(o.\"L33_taxonID\"),(o.\"L33_5_taxonID\"),(o.\"L34_taxonID\"),
      (o.\"L34_5_taxonID\"),(o.\"L35_taxonID\"),(o.\"L37_taxonID\"),(o.\"L40_taxonID\"),
      (o.\"L43_taxonID\"),(o.\"L44_taxonID\"),(o.\"L45_taxonID\"),(o.\"L47_taxonID\"),
      (o.\"L50_taxonID\"),(o.\"L53_taxonID\"),(o.\"L57_taxonID\"),(o.\"L60_taxonID\"),
      (o.\"L67_taxonID\"),(o.\"L70_taxonID\")
    ) x(ancestor_id)
    JOIN expanded_taxa anc ON anc.\"taxonID\" = x.ancestor_id
    WHERE anc.\"rankLevel\" <= ${globalMaxRank}
  )
  SELECT array_agg(potential_ancestors.taxon_id) AS allowed_ancestors
  FROM potential_ancestors
) TO STDOUT WITH CSV HEADER;
"
    local query_result
    query_result="$(execute_sql "$sql")"

    # If the query returns only a header line, it might indicate no row found
    # for that root. We can check for 'allowed_ancestors' in the last line.
    local data_line
    data_line="$(echo "$query_result" | tail -n1)"
    if [[ "$data_line" == *"allowed_ancestors"* ]]; then
      echo "ERROR: check_root_independence: No row found or no ancestors for taxonID=${tid}" >&2
      return 1
    fi

    # data_line might look like: {47158,47157,47120,...}
    # We'll remove braces and parse
    local trimmed="$(echo "$data_line" | tr -d '{}')"
    # e.g. 47158,47157,47120
    # We'll split on commas
    IFS=',' read -ra ancestors <<< "$trimmed"

    # Now store them in space-separated form
    rootSets["$i"]="${ancestors[*]}"
  done

  # 3) Compare each pair of sets for intersection
  for ((i=0; i<${#roots[@]}; i++)); do
    for ((j=i+1; j<${#roots[@]}; j++)); do
      local set1=" ${rootSets[$i]} "
      for t2 in ${rootSets[$j]}; do
        # If the token t2 appears in set1 => overlap
        # (We assume space-bounded match to avoid partial string hits)
        if [[ "$set1" =~ " $t2 " ]]; then
          echo "ERROR: Overlap detected between root #$i (${roots[$i]}) \
and root #$j (${roots[$j]}) on taxonID=${t2}" >&2
          return 1
        fi
      done
    done
  done

  return 0
}

# -------------------------------------------------------------
# D) get_major_rank_floor()
# -------------------------------------------------------------
# This function returns the next-lower major rank multiple of 10 if we want
# to exclude minor ranks. For instance:
#   if input=57 => output=50
#   if input=50 => output=40
#   if input=70 => output=60
#
# If the user wants minor ranks, we might skip or do partial rounding logic.
# For now, we do a straightforward approach:
#
function get_major_rank_floor() {
  local input_rank="$1"
  # We'll do a naive loop:
  # possible major ranks = [70,60,50,40,30,20,10,5]
  # or we can do math: floor((input_rank/10))*10 => but that fails for e.g. 57 => 50 is fine
  # Actually that might be enough, but let's handle if it's exactly a multiple of 10 => we subtract 10 again
  # e.g. 50 => 40, because we want "strictly less than the root rank".
  # If input=57 => floor(57/10)*10=50 => good
  # If input=50 => floor(50/10)*10=50 => but we want 40 => so let's do -10 if exactly multiple

  local base=$(( input_rank/10*10 ))
  if (( $(echo "$input_rank == $base" | bc) == 1 )); then
    # means input is multiple of 10
    base=$(( base-10 ))
  fi
  echo "$base"
}

export -f parse_clade_expression
export -f check_root_independence
export -f get_major_rank_floor