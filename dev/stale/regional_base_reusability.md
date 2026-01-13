- The upper boundary used for ancestor search, which is determine by the CLADE/METACLADE/MACROCLADE, is used for the regional-base tables ()"${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors\"), not on one of the clade-export specific tables in cladistic.sh. So this is at odds with the previous design (before we added ancestor-aware logic), where previously the _all_sp table only varied by the REGION_TAG/MIN_OBS. This is probably OK, and might even be necessary for the purposes of determining the exact set of ancestral taxonIDs that need to be included in the base tables when looking to export more than just research-grade observations (i.e. observations with an uncontested species-level label) but it is a bit of a departure from the previous design. So we need to confirm what the set of taxa in the _all_sp_and_ancestors table depends upon (I think it is only the REGION_TAG/MIN_OBS/boundary ranks), and we can potentially mitigate by adjusting the generated base tables names to include the highest root rank (or highest root ranks, in the case of metaclades with multiple root ranks) used in the ancestor search; this will properly version the regional base tables and prevent reuse of base tables when the ancestor scopes differ.
  - So this means that the boundaries of the ancestor search for generating the regional _all_sp_and_ancestors is defined with respect to the configured clade/metaclade for a job, and so the regional base table might need to be recreated for successive job using clades/metaclades with different root ranks.
    - Really, the ancestor-aware logic should be implemented on the cladistic.sh tables.
    - The regional base table names do not fully capture the 'versining', so e.g. a NAfull_min50_all_sp_and_ancestors table generated from a PTA (metaclade) job would not be reusable for a successive job that used a MACROCLADES["arthropoda"]='("L60_taxonID" = 47120)' macroclade, since the PTA root ranks are lower than the L60 rank-- so that regional base table would be missing L50 ancestors. 
      - This would actually be OK in theory but it might break some downstream assumptions, so it would be better to recreate the regional base table for each successive job if that job uses a different root rank.
      - TODO: Confirm that it is only the root rank, not the root taxonID, that is used to define the ancestor search for the regional base tables.
        - If the regional base table _all_sp_and_ancestors only varies by the REGION_TAG/MIN_OBS/boundary ranks, then we could mitigate by adjusting the generated base tables names to include the highest root rank used in the ancestor search.
        - Otherwise, we would need to include the CLADE/METACLADE/MACROCLADE in the regional base table name.
  - regional base table is an increasingly inappropraite name for this table. It was fine when the tables always just included the species in the region that passed the MIN_OBS threshold/the corresponding observations, but the contents of the table are now dependent on the CLADE/METACLADE/MACROCLADE.
    - This issue was averted for INCLUDE_OUT_OF_REGION_OBS, because the regional base observations table always include all observations for the species in the region that passed the MIN_OBS threshold (and now for all their ancestors in the scope of the ancestor search, too).
      - And then if INCLUDE_OUT_OF_REGION_OBS=false, then we re-applied the bounding box for the final table.
    - There might be a similar mitigation approach we could take for ancestor search here. A much more inclusive set of observations for, i.e. _all_sp_and_ancestors would include all species in the region that passed the MIN_OBS threshold and all the ancestors of those species up to but not including L100 (state of matter), i.e. unrestricted ancestor search. _sp_and_ancestors_obs would include all observations where taxon_id=[<a taxonID from _all_sp_and_ancestors].
      - By default, only search for the major-rank ancestors, i.e. L20, L30, L40, L50, L57, L60, L70. So INCLUDE_MINOR_RANKS_IN_ANCESTORS=false. If INCLUDE_MINOR_RANKS_IN_ANCESTORS=true, then include minor ranks in the unbounded ancestor search, and adjust the table names (_all_sp_and_ancestors_incl_minor_ranks, _sp_and_ancestors_obs_incl_minor_ranks). Searching minor ranks can occur significant performance penalty as only major ranks are indexed, and we will not need to use this in the intermediate future.
      - Possibly do a second ancestor search with only the set of ancestors that are up to the boundary rank for that export? This would be used for the filtering for the final table for that export job.
      - But then, for the final table, we'd need to apply a filter to exclude the observations that fall outside of the scope of the job/clade-specific ancestor search. It gets kind of complicated to define this filter-- do we consider the base taxonID of the observation? Not necessarily, since sometimes we wipe labels of some ranks if the no. observations for that taxonID are too low in the final step (depending on MIN_OCCURRENCES_PER_RANK, which is an alternate floor for wiping labels for higher ranks if the no. occurences for those taxonIDs are too low, while still keeping the observations if they have passing labels for some ranks that are not wiped, e.g. an observation has a non-research grade species label, so we wipe L10_taxonID to null, and it has a L20_taxonID label that is very rare, so occurs less than MIN_OCCURRENCES_PER_RANK in the final table, but it has a usable L30_taxonID label and we want to downstream model to be able to learn that a sample like 'that' should be learned as being in that family (L30).
    - My current standing is that we should do the ancestor search with the constrained upper boundary, and accept that we will lose some reusability between regional base tables between exports that use different clades/metaclades (but maybe can reuse if the ranks of the clades stay constant between jobs, need to confirm).
      - This simplifies the logic in cladistic.sh and preserves the functionality of the existing filters in cladistic.sh.

---

Below is a **high‐level architectural analysis** of the complication you raised about **root‐rank–dependent upper boundaries** for ancestor searches in the _regional base_ tables. We then outline **three possible strategies** (with trade‐offs) to handle it, so you can choose a design that best fits your workflow. Finally, we discuss a **table‐naming** convention to avoid confusion when reusing tables across jobs.

---

## 1. The Complication: “Regional Base” vs. “Clade‐Dependent Boundary”

### Original Assumption
Your “regional base” tables (e.g. `NAfull_min50_all_sp_and_ancestors`) historically **only** depended on:
- **REGION_TAG** (to define bounding box)
- **MIN_OBS** threshold (minimum species observations)

They thus served as a general “base” for subsequent tasks—especially in the old design, before introducing ancestor‐aware logic.

### New Reality
With the new ancestor‐aware approach, **which** ancestors get included in the “base” table can also depend on:
- The **root rank** (or ranks, for multi‐root metaclades) that define how high in the taxonomy you gather ancestors.  
- The **INCLUDE_MINOR_RANKS_IN_ANCESTORS** toggle (whether you skip or include sublevels like L11, L13, etc.).

This means the “base” table’s contents are **no longer** universal. If your user picks a metaclade with root rank=50, you might gather ancestors only up to rank<40; or if the user picks root rank=60, you gather up to rank<50. Another job may want the entire “Arthropoda” domain or even an unbounded approach. Consequently, your “base” table changes based on the clade or macroclade used.

**Implication**: A single “NAfull_min50_all_sp_and_ancestors” table is **no longer** guaranteed to be correct or complete for all clade exports. If it was built for a certain rank boundary, it might miss some ancestors needed for a different rank boundary in a later job. This breaks the old assumption that the same “base” can be safely reused.

---

## 2. Three Potential Strategies

### **Strategy A: Create a “Maximal” Ancestor Base Once, Then Filter Later**
1. Always gather **all** ancestors up to the broadest possible rank—for example, up to L70 (or L60) for every species that meets MIN_OBS.  
2. This produces an **all‐encompassing** base table, large but fully inclusive.  
3. In your subsequent “cladistic” step (or some final filtering step), you apply the user’s rank boundaries to remove any ancestors above that user’s chosen limit.

**Pros**  
- You get a single “_all_sp_and_ancestors” table per region (and MIN_OBS) that can be reused across all jobs.  
- No repeated table creation for each clade/macroclade.  
- Maintains the older “regional_base” idea: the table only depends on region & MIN_OBS.

**Cons**  
- Potentially **bigger** table with more ancestors than needed for a narrower clade.  
- Slightly **slower** queries and merges in some workflows, because you must store and then filter out unneeded ancestors.

### **Strategy B: Always Build Job‐Specific “Regional Base” Tables**
1. The “_all_sp_and_ancestors” table is **no longer** purely region‐based; it also includes the job’s rank boundary.  
2. If a user picks a new clade with a different rank boundary, we **rebuild** that table.  
3. Name the table to reflect both region/min obs **and** the boundary rank(s). For multi‐root, store the highest rank or even each root rank in the name.

**Pros**  
- Each job’s table is precisely tailored to the chosen clade and rank boundary.  
- Minimal extraneous data.  
- No potential confusion about whether an old table had the right upper boundary.

**Cons**  
- Table creation is repeated for each new job/clade. This is more time‐consuming.  
- If you want to **reuse** tables across multiple similar exports, you need to ensure the boundaries match exactly—and if not, you must build a new table.

### **Strategy C: Hybrid Approach**
1. Maintain a “maximal” ancestor table up to L60 or L70 for each region.  
2. For narrower clades (like root=50 or 57), do an additional quick pass that **filters** out ancestors beyond that rank from the final step.  
   - This can happen in your “cladistic.sh” or in a second ephemeral table.  
3. If someone later chooses a new clade with a bigger boundary, you might have to rebuild the “maximal” table if it wasn’t big enough.

This approach tries to strike a **balance**—you keep a fairly inclusive base so you do not have to rebuild for every small change in rank, but if someone picks an even higher rank than you accounted for, you do a one‐off rebuild.

---

## 3. Table‐Naming Conventions to Avoid Confusion

No matter which strategy you adopt, you may want to embed the relevant boundary/flags into the table name if it can vary from job to job. For instance:

1. **If Strategy B** (job‐specific):  
   - `NAfull_min50_all_sp_and_ancestors_root50` or  
   - `NAfull_min50_all_sp_and_ancestors_macroL60`  
   - Possibly also `_minorTrue` if `INCLUDE_MINOR_RANKS_IN_ANCESTORS=true`.

2. **If Strategy A** (maximal base):  
   - `NAfull_min50_all_sp_and_ancestors_upToL70`  
   - Then you know it’s big enough for any clade up to rank=70.

Either way, ensure the name **uniquely** identifies the maximum rank boundary or any toggles (like “minor rank included”), so you do not accidentally skip regeneration for a job that needs a different boundary.

---

## 4. Additional Observations

1. **Performance & Indexing**  
   - If you gather many “unnecessary” ancestors, you might see performance slowdowns. Conversely, building many separate base tables for each job has overhead. Balancing these trade‐offs depends on how frequently you run these jobs, how large your dataset is, and how often your rank boundaries differ.

2. **Potential for a “cladistic” Pre‐Step**  
   - As you noted, if the “regional base” is truly region + MIN_OBS only, then you can do the clade‐specific ancestor unrolling in `cladistic.sh`. But that means the “regional base” table might not contain the ancestor taxonIDs at all, which in turn means the “cladistic” step must do the entire unrolling from species to top rank.  
   - Some teams prefer that approach so the “regional base” table remains purely region + species threshold only. Others want that ancestor logic **up front** (especially if they do multiple exports that rely on the same ancestor set).

3. **Minor vs. Major Ranks**  
   - If you do a “maximal” approach, do you also include minor ranks in your final base table? If you rarely need them, you might skip them in that “maximal” approach to avoid ballooning table size.  
   - Alternatively, you create two “maximal” base variants: `_inclMinor` and `_majorOnly`.

4. **Reusability**  
   - The core question: **Is reusability across multiple exports important enough** to maintain a single maximal table? Or is your pipeline ephemeral enough that building a job‐specific table is acceptable? If you do many exports with different rank boundaries, building a single superset table might be more efficient overall.

---

## 5. Summary: “Yes, We’re Departing from the Old Reuse Model”

- **You are correct** that once you tie the ancestor search to the user’s chosen root rank(s), you lose a one‐size‐fits‐all “regional base.”  
- **This is normal** for advanced multi‐clade or multi‐metaclade logic. Many solutions **either** do all unrolling in a final filtering step (so the base remains purely region + species) **or** accept that the base is job‐specific and rename it accordingly.

Ultimately, **the simplest resolution** is to **pick a strategy** for how large (or small) you want your “regional base” table to be:

- If you want a single multi‐purpose base, go for **Strategy A** and gather ancestors up to L60 or L70 for everyone. Then rely on `cladistic.sh` to further refine the boundary.  
- If you prefer a tight alignment of “base table == the exact set of ancestors for a particular job,” adopt **Strategy B**.  
- If you have moderate variety in rank boundaries, but not an enormous range, you could do **Strategy C**—some partial superset approach.

In any case, you’ll want to revise your table naming convention to reflect the **boundary ranks** (and possibly the minor‐rank inclusion setting) to avoid accidental reuse of an incompatible table.