#!/bin/bash
# ------------------------------------------------------------------------------
# clade_defns.sh
# ------------------------------------------------------------------------------
# This file defines the integer-based filtering expressions for macroclades,
# clades, and metaclades, referencing columns in "expanded_taxa".
#
# Usage:
#   source clade_defns.sh
#   Then pick a macroclade (MACROCLADE="..."), or a clade (CLADE="..."),
#   or a metaclade (METACLADE="...") in your environment, and the
#   cladistic.sh script will build a condition from one of the arrays below.
#
# Example:
#   MACROCLADES["arthropoda"]='("L60_taxonID" = 47120)'
#   CLADES["insecta"]='("L50_taxonID" = 47158)'
#   METACLADES["primary_terrestrial_arthropoda"]='("L50_taxonID" = 47158 OR "L50_taxonID" = 47119)'
#
# Be sure to substitute the correct taxonIDs for your local database!
# ------------------------------------------------------------------------------
#
# Sections in this file:
#   1) Macroclade Definitions
#   2) Clade Definitions
#   3) Metaclade Definitions
#   4) get_clade_condition() helper
#
# NOTE: We do NOT remove any existing definitions or comments.

# ---[ 1) Macroclade Definitions ]---------------------------------------------
# Typically for kingdom-level (L70) or phylum-level (L60) anchors.

declare -A MACROCLADES

# 1) Arthropoda => phylum at L60 = 47120
MACROCLADES["arthropoda"]='("L60_taxonID" = 47120)'

# 2) Chordata => phylum at L60 = 2
MACROCLADES["chordata"]='("L60_taxonID" = 2)'

# 3) Plantae => kingdom at L70 = 47126
MACROCLADES["plantae"]='("L70_taxonID" = 47126)'

# 4) Fungi => kingdom at L70 = 47170
MACROCLADES["fungi"]='("L70_taxonID" = 47170)'

# (Optional) If you consider Actinopterygii, Mammalia, Reptilia, etc.
# to be "macroclades," you may define them here instead of in CLADES.
# For instance:
#   MACROCLADES["mammalia"]='("L50_taxonID" = 40151)'


# ---[ 2) Clade Definitions ]--------------------------------------------------
# Typically for class-level (L50), order-level (L40), or narrower taxonomic groups.
# single-root, so functionally equivalent to METACLADES.

declare -A CLADES

# -- Plant Clades (Subphylum and Class levels) --
# -- Plant Subphylum (L57) --
CLADES["angiospermae"]='("L57_taxonID" = 47125)' # flowering plants

# -- Plant Classes (L50) --
CLADES["liliopsida"]='("L50_taxonID" = 47163)'    # monocots
CLADES["magnoliopsida"]='("L50_taxonID" = 47124)' # dicots

# -- Class-level (L50) Examples --
CLADES["actinopterygii"]='("L50_taxonID" = 47178)'
CLADES["amphibia"]='("L50_taxonID" = 20978)'
CLADES["arachnida"]='("L50_taxonID" = 47119)'
CLADES["aves"]='("L50_taxonID" = 3)'
CLADES["insecta"]='("L50_taxonID" = 47158)'
CLADES["mammalia"]='("L50_taxonID" = 40151)'
CLADES["reptilia"]='("L50_taxonID" = 26036)'

# -- Order-level (L40) Examples --
CLADES["testudines"]='("L40_taxonID" = 39532)'
CLADES["crocodylia"]='("L40_taxonID" = 26039)'
CLADES["coleoptera"]='("L40_taxonID" = 47208)'
CLADES["lepidoptera"]='("L40_taxonID" = 47157)'
CLADES["hymenoptera"]='("L40_taxonID" = 47201)'
CLADES["hemiptera"]='("L40_taxonID" = 47744)'
CLADES["orthoptera"]='("L40_taxonID" = 47651)'
CLADES["odonata"]='("L40_taxonID" = 47792)'
CLADES["diptera"]='("L40_taxonID" = 47822)'

# -- Additional Named Groups (Suborders, Clade Subsets, etc.) --
# Pterygota => The DB shows two taxonIDs (184884, 418641) plus
# another entry with L40_taxonID=48796. We combine them with OR:
CLADES["pterygota"]='("taxonID" = 184884 OR "taxonID" = 418641 OR "L40_taxonID" = 48796)'

# Phasmatodea => Not found in your query results. If/when you know its ID,
# you can fill it in here:
# CLADES["phasmatodea"]='("L40_taxonID" = ???)'

# Subclades within Hymenoptera (all share L40_taxonID=47201).
# Typically, referencing the top-level order is "hymenoptera"
# while these might be more specific anchor taxa:
CLADES["aculeata"]='("taxonID" = 326777)'
CLADES["apoidea"]='("taxonID" = 47222)'
CLADES["formicidae"]='("taxonID" = 47336)'
CLADES["vespoidea"]='("taxonID" = 48740)'
CLADES["vespidae"]='("taxonID" = 52747)'


# ---[ 3) Metaclade Definitions ]----------------------------------------------
# Multi-root or cross-macroclade definitions. Compose bigger groups using OR.

declare -A METACLADES

# Example 1: primary_terrestrial_arthropoda (pta) => Insecta OR Arachnida.
METACLADES["pta"]='("L50_taxonID" = 47158 OR "L50_taxonID" = 47119)'

# Example 2: flying_vertebrates => Birds (aves) OR Bats (chiroptera)
# METACLADES["flying_vertebrates"]='("L50_taxonID" = 3 OR "L40_taxonID" = 7721)'

# Example 3: nonavian_reptiles => reptilia minus birds.
# METACLADES["nonavian_reptiles"]='("L50_taxonID" = 26036 AND "L50_taxonID" != 3)'


# ---[ 4) get_clade_condition() Helper ]-----------------------------------------
# Picks the correct expression given environment variables (METACLADE, CLADE,
# MACROCLADE). This is used by cladistic.sh to filter rows.

function get_clade_condition() {
  local condition

  # 1) If METACLADE is set (and found in METACLADES), return that
  if [[ -n "${METACLADE}" && -n "${METACLADES[${METACLADE}]}" ]]; then
    condition="${METACLADES[${METACLADE}]}"
    echo "${condition}"
    return
  fi

  # 2) Else if CLADE is set
  if [[ -n "${CLADE}" && -n "${CLADES[${CLADE}]}" ]]; then
    condition="${CLADES[${CLADE}]}"
    echo "${condition}"
    return
  fi

  # 3) Else if MACROCLADE is set
  if [[ -n "${MACROCLADE}" && -n "${MACROCLADES[${MACROCLADE}]}" ]]; then
    condition="${MACROCLADES[${MACROCLADE}]}"
    echo "${condition}"
    return
  fi

  # 4) Fallback: no recognized key => no filter
  echo "TRUE"
}

export -f get_clade_condition