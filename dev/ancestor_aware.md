# 1. Overview

We plan to introduce an **ancestor‐aware approach** into our **iNaturalist data export pipeline** to better support hierarchical classification tasks. Currently, our pipeline focuses only on species that meet a minimum threshold of research‐grade observations in the bounding box and does not systematically gather all their ancestral taxa (e.g., genus, family, order). This design limits the data’s usefulness in scenarios where the model must “know when to stop”—i.e., return a coarser taxonomic label for rare or partially identified specimens. By explicitly collecting each species’s ancestors, we can generate training data that captures the broad taxonomic context for each in‐threshold species, plus partial observations for species that do not meet the threshold but are still informative at higher ranks. Furthermore, new user requirements—such as allowing a user to specify a root rank (not always L70) and automatically wiping low‐occurrence taxa—underscore the need for a flexible, robust mechanism to unify coarse and fine ranks in a single workflow.

# 2. Requirements & Goals

1. **Ancestor Inclusion**  
   - For each species that meets the regional threshold (`MIN_OBS` of research‐grade observations), we must add all relevant ancestral taxa (genus, family, order, etc.) up to a specified root rank. This ensures we do not discard potentially valuable coarser labels.

2. **Root Rank Flexibility**  
   - The user may define a “clade root” to limit how far up we gather ancestors (e.g., only up to L40=order if `CLADE` is at L50=class).  
   - If the user provides a multi‐root `METACLADE`, we repeat the logic for each root.  

3. **Preserving Partial Observations**  
   - Observations of rare species (below the threshold) must still be included if they share an ancestor with a species that meets the threshold. Example: a species that has only 20 research‐grade observations might be worthless for species‐level classification, but still valuable for genus/family modeling.  

4. **Low‐Occurrence Taxon Wiping**  
   - Even after we gather the full lineage, if a particular taxon (say a genus with few total occurrences) fails to meet a user‐configured threshold, we wipe its label from the relevant observations. This prevents the model from trying to learn extremely rare or ill‐defined ranks, while still retaining the rest of the observation’s taxonomic ranks if they exceed the threshold.

5. **Integration with Existing Pipeline**  
   - The solution must integrate cleanly with the existing code structure: `regional_base.sh` for building the base set of species, and `cladistic.sh` for applying final logic.  
   - We also must consider how `SKIP_REGIONAL_BASE=true` and table naming might need to accommodate new parameters or extended logic, ensuring we do not skip creation of a base table that should differ.

# 3. Proposed Approaches

Below are conceptual solutions to implement the ancestor‐aware feature, balancing correctness, performance, and maintainability.

1. **Phase 1 (Species Selection):**  
   - Unchanged at first: gather species that meet `MIN_OBS` in the bounding box. This set becomes \( S \).  
   - For each species in \( S \), we identify its ancestors up to a user‐defined or clade‐derived root rank. This step queries `expanded_taxa` to retrieve `L20_taxonID`, `L30_taxonID`, etc.

2. **Phase 2 (Ancestor Inclusion):**  
   - Compute the union of all ancestor IDs for the species in \( S \). Denote that union as \( T \).  
   - Combine \( S \cup T \) to form `_all_taxa`.  
   - `_all_taxa_obs` is then defined as **all** observations whose `taxon_id` is in `_all_taxa`. If `INCLUDE_OUT_OF_REGION_OBS=true`, we include those observations globally; if not, we reapply the bounding box.  

3. **Phase 3 (Filtering & Wiping):**  
   - Once `_all_taxa_obs` is formed, we apply any logic that wipes certain ranks if they fail an absolute threshold. For instance, if a genus `G` has fewer than `MIN_OBS_GENUS` occurrences, we set `L20_taxonID=NULL` on all relevant rows, effectively turning them into coarser labels.  
   - We might also unify or refine the rank threshold with the existing `RG_FILTER_MODE` concept.

4. **Table Naming & Skip Logic:**  
   - If `INCLUDE_OUT_OF_REGION_OBS` or other new variables impact the final set of `_all_taxa`, we can incorporate them into the naming pattern of the base table, e.g., `<REGION_TAG>_min${MIN_OBS}_IOORtrue_ancestors_all_taxa`. This reduces confusion about whether a table truly matches the current pipeline parameters.  
   - Alternatively, we could skip storing `_all_taxa` entirely and build the final `_all_taxa_obs` in one pass. But storing `_all_taxa` can be helpful for debugging or subsequent reuse.

5. **Performance & Indices:**  
   - Gathering ancestors for each species might be expensive if we do it row by row. We can rely on `expanded_taxa` columns and a single or few set-based queries. For instance, do a join on `expanded_taxa` once, unnest relevant columns (up to the root rank), and deduplicate.

# 4. Decision & Summary

We will adopt a **single pass** approach to ancestor inclusion at the end of `regional_base.sh`:

- **After** we identify the in-threshold species, we gather their ancestors via a SQL query that unrolls `L10_taxonID`, `L20_taxonID`, etc. up to the chosen root rank.  
- The union of those IDs with the species set becomes `_all_taxa`.  
- Then `_all_taxa_obs` is formed by including all observations referencing any ID in `_all_taxa`, subject to bounding-box toggles.  
- Next, in `cladistic.sh`, we optionally wipe certain ranks (genus/family/etc.) if they fail a usage threshold. We also apply `RG_FILTER_MODE` for research vs. non‐research filtering.

**Key Gains:**
- We correctly keep partial-labeled or rare species observations.  
- Observations referencing a genus or family are still included, even if that rank wasn’t physically observed in bounding box, because it is the ancestor of a species in the region.  
- `INCLUDE_OUT_OF_REGION_OBS` remains a toggle controlling whether we gather out-of-region records for the selected `_all_taxa`.  

# 5. Optional: Future Extensions

1. **Multi‐Rank Thresholds**  
   - We might eventually define distinct `MIN_OBS` for genus vs. family vs. species. This would refine or unify partial-labeled data.  
2. **Selective Mix of “Ancestor Only”**  
   - In some cases, the user might not want to preserve, say, all L70=kingdom observations. We could define a cut at `L50` or `L40`.  
3. **Precomputed Caches**  
   - For large datasets, we might precompute each species’s ancestry in a separate table to avoid repeated unnest queries.  

# 6. Implementation Plan

Below is the plan for introducing ancestor‐aware functionality and partial‐rank handling. We integrate the new user requirements: (1) gathering ancestral taxa for each species that meets the bounding‐box threshold, up to a user‐specified root rank, and (2) automatically “wiping” taxonIDs that fail an extended usage threshold. We also clarify table naming conventions so that skip logic in `main.sh` can be consistently applied.

## 6.1 Step‐by‐Step Outline

1. **Extend `regional_base.sh` to produce two base tables**:  
   - **`<REGION_TAG>_min${MIN_OBS}_all_sp`**: This is the current table of *just* species (rank=10) that pass the research‐grade threshold in region.  
   - **`<REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors`**: A table that includes each species from the first table plus all of its ancestral taxonIDs (up to the root rank).  
     - **CLARIFY**: If `CLADE`=“angiospermae” is at L57, we only gather ancestors up to L50. If `METACLADE` is multi‐root, we do the same for each root.  
     - To build this, we join `<REGION_TAG>_min${MIN_OBS}_all_sp` to `expanded_taxa e` on `e."taxonID" = species_id`, then unnest or gather columns L10, L20, etc., up to the user’s root rank, and insert them into the final table.  

2. **Form the final `_all_taxa_obs` using the union of those IDs**:  
   - Once we have `<REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors` (the union of species plus any ancestors), we can produce `<REGION_TAG>_min${MIN_OBS}_all_taxa_obs` the same way we do now, except the condition is:  
     - `observations.taxon_id` in `(SELECT taxon_id FROM <REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors)`  
     - If `INCLUDE_OUT_OF_REGION_OBS=false`, we re‐apply bounding box. If `true`, we do not.  
   - **CLARIFY**: We must confirm how skip logic and table naming incorporate `INCLUDE_OUT_OF_REGION_OBS`. Possibly name the table `"_all_sp_and_ancestors_obs_ioorFalse"` if `INCLUDE_OUT_OF_REGION_OBS=false`, etc.  

3. **Refine `cladistic.sh`** to handle partial labeling logic:  
   1. **RG_FILTER_MODE** remains as is for controlling research‐grade vs. non‐research, species vs. genus, etc.  
   2. **Introduce the new “taxon usage threshold”**: e.g. `MIN_OCCURRENCES_PER_RANK`. If a rank’s usage is below that threshold, we nullify that rank for each relevant observation.  
      - We can do this after the table creation by an `UPDATE` pass: “UPDATE `<EXPORT_GROUP>_observations` SET L20_taxonID = NULL if L20_taxonID is below threshold, etc.” Or we embed a join in the creation query that checks usage counts.  
      - The usage count for each taxon can be computed by grouping `<REGION_TAG>_min${MIN_OBS}_all_taxa_obs` or `<EXPORT_GROUP>_observations`. If a particular `L20_taxonID` or `L30_taxonID` has fewer than `MIN_OCCURRENCES_PER_RANK` occurrences, it is wiped.  
   3. The final CSV export subqueries remain the same (two subqueries unioned: capped research species vs. everything else).

4. **Adjust Table Naming & Skip Logic**:  
   - To avoid collisions:  
     1. **`<REGION_TAG>_min${MIN_OBS}_all_sp`** for the species list.  
     2. **`<REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors`** for the union of species + their ancestors.  
     3. **`<REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors_obs`** (with `_ioorTrue` or `_ioorFalse` suffix if we want) for the final base observations table.  
   - Then in `main.sh`, if `SKIP_REGIONAL_BASE=true`, we check for the presence of exactly the right table name. If we see partial or missing suffix, we know it’s not the same config.

5. **Implement “Root Rank” Logic**:  
   - For a single `CLADE` or `MACROCLADE` (like “amphibia” at L50=20978), gather ancestors only up to L40, or up to user’s specified rank. Possibly store this in an env var `ANCESTOR_ROOT_RANKLEVEL`. If `METACLADE` is multi‐root, we do it for each root and union them.  
   - This approach ensures we do not ascend beyond the clade definition. We can store a small dictionary of known ranklevels for the user’s clade roots, or parse from `clade_defns.sh`.

6. **Performance & Indices**:  
   - Each step might do large set operations if we have many species. We can consider an approach:  
     1. Build a temp table for the species set.  
     2. Join to `expanded_taxa` once, unnest columns L10–L70. Filter out columns above `ANCESTOR_ROOT_RANKLEVEL`.  
     3. Insert into the final `_all_sp_and_ancestors`.  
   - If performance is an issue, we might add a partial index or store a precomputed table of “taxon -> all ancestors up to rank=??.” But we can start with the simpler approach first.

## 6.2 Validation & Testing

- **Comparisons** between old pipeline vs. new pipeline with `RG_FILTER_MODE=ONLY_RESEARCH` should yield similar results for species, except we now see additional ancestor taxonIDs in `_all_sp_and_ancestors`.  
- Check the partial-labeled expansions by verifying that extremely rare species rows appear with `L10_taxonID`=NULL in final outputs if `MIN_OCCURRENCES_PER_RANK` is not met.  

## 6.3 Proposed “Incremental” Implementation

1. **Add** code in `regional_base.sh`:
   - Create `..._all_sp`.  
   - Gather ancestors into `..._all_sp_and_ancestors`.  
   - Then produce the final `..._all_sp_and_ancestors_obs`.  
2. **Update** `main.sh` skip logic to search for the new table name. Possibly unify naming with `ANCESTOR_ROOT_RANKLEVEL` or `INCLUDE_OUT_OF_REGION_OBS`.  
3. **Refine** `cladistic.sh`:
   - Insert a step or function that checks usage counts for each rank (20, 30, etc.) and overwrites them with NULL if below threshold. This can be done via an `UPDATE` or a left join with a usage table.  
   - Retain the union approach for final CSV export.  

---

# 7. Additional Planning / Checklists

**7.1 Confirm Known Variables & Defaults**  
1. `ANCESTOR_ROOT_RANKLEVEL`: Derive from user’s clade definitions. If user picks “amphibia” at L50, set this to 40 if they only want up to order.  
2. `MIN_OCCURRENCES_PER_RANK`: If not specified, default to the same `MIN_OBS`.  
3. If `CLARIFY:` is needed for multi‐root `METACLADES`, confirm how we store or pass multiple root ranklevels.

**7.2 Table Name Finalization**  
- Need consistent naming. e.g. `NAfull_min50_sp`, `NAfull_min50_sp_and_ancestors`, `NAfull_min50_sp_and_ancestors_obs_ioorTrue`. This ensures we never skip incorrectly.

**7.3 Potential Edge Cases**  
1. A species might have no recognized ancestors up to the root rank if the DB is incomplete. We handle that gracefully by an empty union.  
2. Rare rank usage. If a genus is used 5 times, but the user sets `MIN_OCCURRENCES_PER_RANK=10`, we wipe L20 for those rows. They might still keep L30 or L40 if those are above threshold.  
3. Multi‐root `METACLADES`. We gather ancestors for each root, union them, and proceed.

**7.4 Next Steps**  
- After finalizing the plan, we’ll proceed to **Phase 3**: coding. We’ll create a new `regional_base.sh` block for ancestor inclusion, rename or unify table creation, and augment `cladistic.sh` for partial rank wiping.

---

# 8. Implementation Progress & Updates

- **[x]** Completed detailed design in Phase 2 (sections 6–7).
- **[x]** Implemented new logic in `regional_base.sh` to:
  - Create `<REGION_TAG>_min${MIN_OBS}_all_sp` (just in-threshold species).
  - Gather all ancestors up to the user’s specified root rank (or each root rank if multi-root) to form `<REGION_TAG>_min${MIN_OBS}_all_sp_and_ancestors`.
  - Produce `<REGION_TAG>_min${MIN_OBS}_sp_and_ancestors_obs` (or similarly named) if `INCLUDE_OUT_OF_REGION_OBS=true/false`.
- **[x]** Updated `main.sh` skip logic to incorporate the new table names for accurate detection.
- **[x]** Updated `cladistic.sh` to do partial rank wiping (if `MIN_OCCURRENCES_PER_RANK` is set).  
  - Implemented an `UPDATE` step after `<EXPORT_GROUP>_observations` creation to nullify rank columns that fail usage thresholds.
- **[ ]** **CLARIFY**: The multi-root `METACLADE` approach merges each root rank’s ancestors via union. If user sets 2–3 separate roots, we do a union of all ancestor IDs. This is implemented, but user must confirm test results.

**New Env Vars**:
- **`ANCESTOR_ROOT_RANKLEVEL`** (optional) – user can override automatic root detection if they want to limit the lineage more strictly than the clade’s rank. 
- **`MIN_OCCURRENCES_PER_RANK`** – controls partial label wiping; defaults to same as `MIN_OBS` if unspecified.

# 9. Final Results & Discussion

With these changes:
- **Research**: Rare species are no longer outright removed; even if their species label is invalid for training, they’re retained at coarser ranks.
- **Partial Observations**: We can “wipe” sub-threshold labels, ensuring that extremely rare taxa do not pollute the dataset.
- **Ancestry**: Our new approach systematically gathers each in-threshold species’s ancestors, so the pipeline is now **ancestor‐aware** instead of ignoring unobserved higher-rank taxa.

**Performance**: For very large datasets, we may consider precomputing taxon→ancestors or adding indexes. However, for moderate data, the approach should be sufficiently fast.

**Next Steps**:
- Thorough QA and test runs, especially with multi-root `METACLADE`s. 
- Possibly unify the partial-labeled approach with `RG_FILTER_MODE` if user demands more advanced logic (like skipping research-grade for certain ranks).


---

Can you clarify what you mean in this comment  in clade_helpers.sh?
```
# NOTE: We do not forcibly integrate with existing "get_clade_condition()"
# in clade_defns.sh. Instead, you can call parse_clade_expression() if you
# want to do deeper multi-root logic.
```

Furthermore, on this point:
```
	2.	check_root_independence():
	•	Conceptual approach to gather each root’s ancestry from expanded_taxa, confirm disjoint sets.
	•	Currently placeholders. Implementation details would involve real SQL queries.
```
a conceptual approach is not acceptable. We need to generate the complete implementation of this method:
```
# -------------------------------------------------------------
# C) check_root_independence()
# -------------------------------------------------------------
# This function ensures that each root in a multi-root scenario
# is truly independent. That is, no root is an ancestor or descendant
# of another. We do so by building the set of ancestor IDs for each root,
# then verifying disjointness pairwise.
#
# usage: check_root_independence "myDatabaseName" rootArray
#   rootArray: an array of "rank=taxonID" strings, e.g. "50=47158"
# We assume we can run a quick query on 'expanded_taxa' to gather
# the ~30 possible ancestor columns for each root's row, then compare sets.
#
# If overlap is found, we can either abort or print a warning. We'll choose to abort here.
#
function check_root_independence() {
  local dbName="$1"
  shift
  local roots=("$@")  # e.g. ("50=47158" "60=9999")

  if [ "${#roots[@]}" -le 1 ]; then
    # Nothing to check
    return 0
  fi

  # We'll build arrays of sets. For each root r_i, gather its expanded ancestry.
  declare -A rootSets  # a map from index to "list of taxonIDs"

  for i in "${!roots[@]}"; do
    local pair="${roots[$i]}"
    local rank="${pair%%=*}"
    local tid="${pair##*=}"

    # We'll do a single row fetch in expanded_taxa where taxonID=tid,
    # gather all columns "L5_taxonID", "L10_taxonID", ... "L70_taxonID".
    # Then store them in a set in memory.
    # We'll do a naive approach: psql call, parse results, etc.

    # Real code might do:
    # row=$(docker exec ...)
    # Then parse. For now, we conceptualize a pseudo-result.

    # For demonstration, let's pretend we run:
    # row_of_ancestors might look like "47158|47157|...|<some nulls>"
    # We'll parse them into an array, ignoring nulls.

    # We'll store them in e.g. rootSets["$i"] as "47158 47157 1" etc.
    # PSEUDOCODE:
    # (No real code, just conceptual)

    # rootSets["$i"]="${list_of_ancestors}"

    # For the sake of demonstration, we'll skip real queries.

    # <snip>
    :
  done

  # Now compare pairwise sets for overlap
  for ((i=0; i<${#roots[@]}; i++)); do
    for ((j=i+1; j<${#roots[@]}; j++)); do
      # Compare rootSets["$i"] and rootSets["$j"] for intersection
      # If non-empty => abort
      # PSEUDOCODE:
      # overlapCheck ...
      # if [ "$foundOverlap" = "true" ]; then
      #   echo "ERROR: Overlap detected between root i and j"
      #   return 1
      # fi
      :
    done
  done

  return 0
}

```

You may wish to analyze the exact structure of the expanded_taxa table to assist in the completion:
```
ibrida-v0-r1=# \d expanded_taxa
                        Table "public.expanded_taxa"
      Column      |          Type          | Collation | Nullable | Default
------------------+------------------------+-----------+----------+---------
 taxonID          | integer                |           | not null |
 rankLevel        | double precision       |           |          |
 rank             | character varying(255) |           |          |
 name             | character varying(255) |           |          |
 taxonActive      | boolean                |           |          |
 L5_taxonID       | integer                |           |          |
 L5_name          | character varying(255) |           |          |
 L5_commonName    | character varying(255) |           |          |
 L10_taxonID      | integer                |           |          |
 L10_name         | character varying(255) |           |          |
 L10_commonName   | character varying(255) |           |          |
 L11_taxonID      | integer                |           |          |
 L11_name         | character varying(255) |           |          |
 L11_commonName   | character varying(255) |           |          |
 L12_taxonID      | integer                |           |          |
 L12_name         | character varying(255) |           |          |
 L12_commonName   | character varying(255) |           |          |
 L13_taxonID      | integer                |           |          |
 L13_name         | character varying(255) |           |          |
 L13_commonName   | character varying(255) |           |          |
 L15_taxonID      | integer                |           |          |
 L15_name         | character varying(255) |           |          |
 L15_commonName   | character varying(255) |           |          |
 L20_taxonID      | integer                |           |          |
 L20_name         | character varying(255) |           |          |
 L20_commonName   | character varying(255) |           |          |
 L24_taxonID      | integer                |           |          |
 L24_name         | character varying(255) |           |          |
 L24_commonName   | character varying(255) |           |          |
 L25_taxonID      | integer                |           |          |
 L25_name         | character varying(255) |           |          |
 L25_commonName   | character varying(255) |           |          |
 L26_taxonID      | integer                |           |          |
 L26_name         | character varying(255) |           |          |
 L26_commonName   | character varying(255) |           |          |
 L27_taxonID      | integer                |           |          |
 L27_name         | character varying(255) |           |          |
 L27_commonName   | character varying(255) |           |          |
 L30_taxonID      | integer                |           |          |
 L30_name         | character varying(255) |           |          |
 L30_commonName   | character varying(255) |           |          |
 L32_taxonID      | integer                |           |          |
 L32_name         | character varying(255) |           |          |
 L32_commonName   | character varying(255) |           |          |
 L33_taxonID      | integer                |           |          |
 L33_name         | character varying(255) |           |          |
 L33_commonName   | character varying(255) |           |          |
 L33_5_taxonID    | integer                |           |          |
 L33_5_name       | character varying(255) |           |          |
 L33_5_commonName | character varying(255) |           |          |
 L37_taxonID      | integer                |           |          |
 L37_name         | character varying(255) |           |          |
 L37_commonName   | character varying(255) |           |          |
 L40_taxonID      | integer                |           |          |
 L40_name         | character varying(255) |           |          |
 L40_commonName   | character varying(255) |           |          |
 L43_taxonID      | integer                |           |          |
 L43_name         | character varying(255) |           |          |
 L43_commonName   | character varying(255) |           |          |
 L44_taxonID      | integer                |           |          |
 L44_name         | character varying(255) |           |          |
 L44_commonName   | character varying(255) |           |          |
 L45_taxonID      | integer                |           |          |
 L45_name         | character varying(255) |           |          |
 L45_commonName   | character varying(255) |           |          |
 L47_taxonID      | integer                |           |          |
 L47_name         | character varying(255) |           |          |
 L47_commonName   | character varying(255) |           |          |
 L50_taxonID      | integer                |           |          |
 L50_name         | character varying(255) |           |          |
 L50_commonName   | character varying(255) |           |          |
 L53_taxonID      | integer                |           |          |
 L53_name         | character varying(255) |           |          |
 L53_commonName   | character varying(255) |           |          |
 L57_taxonID      | integer                |           |          |
 L57_name         | character varying(255) |           |          |
 L57_commonName   | character varying(255) |           |          |
 L60_taxonID      | integer                |           |          |
 L60_name         | character varying(255) |           |          |
 L60_commonName   | character varying(255) |           |          |
 L67_taxonID      | integer                |           |          |
 L67_name         | character varying(255) |           |          |
 L67_commonName   | character varying(255) |           |          |
 L70_taxonID      | integer                |           |          |
 L70_name         | character varying(255) |           |          |
 L70_commonName   | character varying(255) |           |          |
Indexes:
    "expanded_taxa_pkey" PRIMARY KEY, btree ("taxonID")
    "idx_expanded_taxa_l10_taxonid" btree ("L10_taxonID")
    "idx_expanded_taxa_l20_taxonid" btree ("L20_taxonID")
    "idx_expanded_taxa_l30_taxonid" btree ("L30_taxonID")
    "idx_expanded_taxa_l40_taxonid" btree ("L40_taxonID")
    "idx_expanded_taxa_l50_taxonid" btree ("L50_taxonID")
    "idx_expanded_taxa_l60_taxonid" btree ("L60_taxonID")
    "idx_expanded_taxa_l70_taxonid" btree ("L70_taxonID")
```
Otherwise you should have enough information about the interfaces and requirements for the check_root_independence() method to implement it fully. 

Return the complete implementation of the method. Assume that the expanded_taxa table is always available. You could use the execute_sql() method from function.sh for the execution of any queries (assuming that this function can return in the form we need), or add a new function if needed to execute the actual SQL commands:
```
#!/bin/bash

# Common functions used across export scripts

# Function to execute SQL commands
execute_sql() {
    local sql="$1"
    docker exec ${DB_CONTAINER} psql -U ${DB_USER} -d "${DB_NAME}" -c "$sql"
}

....
```
I'm assuming that the DB_CONTAINER, DB_USER, and DB_NAME env vars will be defined in the scope that this function is called. The expanded_taxa table will always be available on the same database as all the other tables we are working with (so just use the DB_ env vars used elsewhere in the flow).

Were there any other 'conceptual' incomplete implementations in your most recent response? If so, you need to return full implementations; taking extra time to think if necessary. 

If not, please return the complete implementation of Section C of clade_helpers.sh:
```
# -------------------------------------------------------------
# C) check_root_independence()
# -------------------------------------------------------------
# This function ensures that each root in a multi-root scenario
# is truly independent. That is, no root is an ancestor or descendant
# of another. We do so by building the set of ancestor IDs for each root,
# then verifying disjointness pairwise.
#
# usage: check_root_independence "myDatabaseName" rootArray
#   rootArray: an array of "rank=taxonID" strings, e.g. "50=47158"
# We assume we can run a quick query on 'expanded_taxa' to gather
# the ~30 possible ancestor columns for each root's row, then compare sets.
#
# If overlap is found, we can either abort or print a warning. We'll choose to abort here.
#
function check_root_independence() {
  local dbName="$1"
  shift
  local roots=("$@")  # e.g. ("50=47158" "60=9999")

  if [ "${#roots[@]}" -le 1 ]; then
    # Nothing to check
    return 0
  fi

  # We'll build arrays of sets. For each root r_i, gather its expanded ancestry.
  declare -A rootSets  # a map from index to "list of taxonIDs"

  for i in "${!roots[@]}"; do
    local pair="${roots[$i]}"
    local rank="${pair%%=*}"
    local tid="${pair##*=}"

    # We'll do a single row fetch in expanded_taxa where taxonID=tid,
    # gather all columns "L5_taxonID", "L10_taxonID", ... "L70_taxonID".
    # Then store them in a set in memory.
    # We'll do a naive approach: psql call, parse results, etc.

    # Real code might do:
    # row=$(docker exec ...)
    # Then parse. For now, we conceptualize a pseudo-result.

    # For demonstration, let's pretend we run:
    # row_of_ancestors might look like "47158|47157|...|<some nulls>"
    # We'll parse them into an array, ignoring nulls.

    # We'll store them in e.g. rootSets["$i"] as "47158 47157 1" etc.
    # PSEUDOCODE:
    # (No real code, just conceptual)

    # rootSets["$i"]="${list_of_ancestors}"

    # For the sake of demonstration, we'll skip real queries.

    # <snip>
    :
  done

  # Now compare pairwise sets for overlap
  for ((i=0; i<${#roots[@]}; i++)); do
    for ((j=i+1; j<${#roots[@]}; j++)); do
      # Compare rootSets["$i"] and rootSets["$j"] for intersection
      # If non-empty => abort
      # PSEUDOCODE:
      # overlapCheck ...
      # if [ "$foundOverlap" = "true" ]; then
      #   echo "ERROR: Overlap detected between root i and j"
      #   return 1
      # fi
      :
    done
  done

  return 0
}
```

Now, looking towards the next steps:
```
	2.	Proposed Next Steps
	•	Step A: Integrate clade_helpers.sh usage in regional_base.sh. For multi-root detection, we call parse_clade_expression(get_clade_condition), partition species, etc.
	•	Step B: Expand check_root_independence() with real SQL queries to gather each root’s ancestor set from expanded_taxa.
	•	Step C: Add boundary logic (get_major_rank_floor()) or minor-rank logic as user toggles in regional_base.sh.
	•	Step D: In cladistic.sh, ensure partial-rank wiping remains consistent with any newly introduced rank columns or edge cases.

```

In your response, please return the complete implementation of Section C on clade_helpers.sh AND prepare a refined, highly specific implementation plan for the remaining steps. Please identify any outstanding clarifications that you will need to return full, robust reimplementations for all remaining steps.