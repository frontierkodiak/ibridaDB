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
#   MACROCLADES["arthropoda"]='("L60_taxonID" = 47119)'
#   CLADES["insecta"]='("L50_taxonID" = 47120)'
#   METACLADES["primary_terrestrial_arthropoda"]='("L50_taxonID" = 47120 OR "L50_taxonID" = 101885)'
#
# Be sure to substitute the correct taxonIDs for your local database!
# ------------------------------------------------------------------------------

# ---[ Macroclades ]-----------------------------------------------------------
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


# ---[ Clades ]----------------------------------------------------------------
# Typically for class-level (L50), order-level (L40), or narrower taxonomic groups.
declare -A CLADES

# -- Plant Clades (Subphylum and Class levels) --
# -- Plant Subphylum (L57) --
CLADES["angiospermae"]='("L57_taxonID" = 47125)' # flowering plants

# -- Plant Classes (L50) --
CLADES["liliopsida"]='("L50_taxonID" = 47163)'    # monocots
CLADES["magnoliopsida"]='("L50_taxonID" = 47124)'  # dicots

# -- Class-level (L50) Examples --

# 1) Actinopterygii => L50 = 47178
CLADES["actinopterygii"]='("L50_taxonID" = 47178)'

# 2) Amphibia => L50 = 20978
CLADES["amphibia"]='("L50_taxonID" = 20978)'

# 3) Arachnida => L50 = 47119
CLADES["arachnida"]='("L50_taxonID" = 47119)'

# 4) Aves => L50 = 3
CLADES["aves"]='("L50_taxonID" = 3)'

# 5) Insecta => L50 = 47158
CLADES["insecta"]='("L50_taxonID" = 47158)'

# 6) Mammalia => L50 = 40151
CLADES["mammalia"]='("L50_taxonID" = 40151)'

# 7) Reptilia => L50 = 26036
CLADES["reptilia"]='("L50_taxonID" = 26036)'


# -- Order-level (L40) Examples --

# 1) Testudines => L40 = 39532
CLADES["testudines"]='("L40_taxonID" = 39532)'

# 2) Crocodylia => L40 = 26039
CLADES["crocodylia"]='("L40_taxonID" = 26039)'

# 3) Coleoptera => L40 = 47208
CLADES["coleoptera"]='("L40_taxonID" = 47208)'

# 4) Lepidoptera => L40 = 47157
CLADES["lepidoptera"]='("L40_taxonID" = 47157)'

# 5) Hymenoptera => L40 = 47201
CLADES["hymenoptera"]='("L40_taxonID" = 47201)'

# 6) Hemiptera => L40 = 47744
CLADES["hemiptera"]='("L40_taxonID" = 47744)'

# 7) Orthoptera => L40 = 47651
CLADES["orthoptera"]='("L40_taxonID" = 47651)'

# 8) Odonata => L40 = 47792
CLADES["odonata"]='("L40_taxonID" = 47792)'

# 9) Diptera => L40 = 47822
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


# ---[ Metaclades ]------------------------------------------------------------
# Multi-root or cross-macroclade definitions. Compose bigger groups using OR/AND.

declare -A METACLADES

# Example 1: terrestrial_arthropods => Insecta OR Arachnida.
# (Using the taxonIDs from the CLADES above.)
METACLADES["terrestrial_arthropods"]='("L50_taxonID" = 47158 OR "L50_taxonID" = 47119)'

# Example 2: flying_vertebrates => Birds (aves) OR Bats (chiroptera)
# Suppose chiroptera => L40=7721 (if that’s valid in your DB).
METACLADES["flying_vertebrates"]='("L50_taxonID" = 3 OR "L40_taxonID" = 7721)'

# Example 3: nonavian_reptiles => reptilia minus birds. You might do:
# METACLADES["nonavian_reptiles"]='("L50_taxonID" = 26036 AND "L50_taxonID" != 3)'


# ---[ Helper Function ]-------------------------------------------------------
# Picks the correct expression given environment variables.
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
