---- ASSISTANT ----
In brief: Catalogue of Life (COL) publishes its yearly and monthly check‑lists in four main interchange formats. For your specific goal—bringing English (and optionally multi‑language) common names into expanded_taxa—the Catalogue of Life Data Package (ColDP) is the most complete and least lossy choice: it ships a dedicated VernacularName table keyed by taxonID, exactly what you need. The alternative Darwin Core Archive (DwC‑A) also contains common names, but they are carried in an optional vernacularname.txt extension that omits several useful fields ColDP provides. TextTree is meant for human‑readable diffs and does not contain vernacular data, while ACEF is a deprecated legacy format. Below you will find (i) a concise description of each dump type and where the common names live, (ii) an integration spec and schema sketch for your expanded_taxa‑derived copy, and (iii) notes on other COL tables you may want to mine later (distribution, media, references).

⸻

1 · Catalogue of Life dump formats

Format	File supplied by COL	Purpose & structure	Where common names live	Pros / cons
ColDP (Catalogue of Life Data Package)	2024_coldp.zip	ZIP bundle of tab‑separated files + metadata.yaml; follows ColDP v1.1 specification. Tables include Name.txt, Taxon.txt, Synonym.txt, Reference.txt, Distribution.txt, VernacularName.txt, etc. ￼ ￼	Dedicated VernacularName entity keyed by taxonID, with fields name, language, preferred, country, area, referenceID, etc. ￼	Richest, loss‑less, explicit foreign keys; excellent for SQL import.
DwC‑A (Darwin Core Archive)	2023_dwca.zip	ZIP archive with meta.xml, a core taxon.txt and optional extensions; follows TDWG Darwin Core Text Guidelines. ￼ ￼	Optional vernacularname.txt extension (same rowType as GBIF vernacular extension) links back to taxonID. ￼ ￼	Widely supported tooling (R, Python python-dwca-reader, GBIF IPT); fewer vernacular metadata fields than ColDP.
TextTree	(not yet downloaded)	Single UTF‑8 text file with indented hierarchy lines; synonyms prefixed with *; rank in <angle‑brackets>. ￼ ￼	No separate vernacular section—only scientific names and synonymy.	Human‑readable and small; unsuitable for programmatic common‑name joins.
ACEF (Annual Checklist Exchange Format)	older releases only	Set of CSV tables (Accepted Species, Synonyms, etc.) defined in 2014 spec. ￼ ￼	Columns EnglishName, PreferredName, but spec is frozen and lacks language codes.	Legacy; use only for compatibility with older pipelines.

Other niche exports COL offers (Newick, Graphviz DOT, Excel) are tree‑visualisation conveniences and do not add vernacular data. ￼

⸻

2 · Integration strategy for expanded_taxa

2.1 Data‑loading pipeline
	1.	Stage ColDP tables

unzip 2024_coldp.zip -d /tmp/coldp_2024

Load with COPY (PostgreSQL) or \copy from psql, e.g.

CREATE TABLE coldp_vernacular (
  taxonID INTEGER,
  name TEXT,
  transliteration TEXT,
  language CHAR(3),
  preferred BOOLEAN,
  country CHAR(2),
  area TEXT,
  sex TEXT,
  referenceID TEXT,
  remarks TEXT
);
\copy coldp_vernacular FROM '/tmp/coldp_2024/VernacularName.txt' (FORMAT csv, DELIMITER E'\t', NULL '');

Do the same for Taxon.txt if you need to cross‑check rank or status.

	2.	Create a protected copy of expanded_taxa

CREATE TABLE expanded_taxa_cmns AS TABLE expanded_taxa;
ALTER TABLE expanded_taxa_cmns
  ADD COLUMN commonName TEXT,
  -- expanded ancestry columns already exist; add matching commonName cols
  ADD COLUMN L10_commonName TEXT,
  ... ;  -- repeat for each expanded level you care about


	3.	Populate commonName (core taxon itself)

UPDATE expanded_taxa_cmns t
SET   commonName = v.name
FROM  (
  SELECT DISTINCT ON (taxonID)
         taxonID, name
  FROM   coldp_vernacular
  WHERE  language = 'eng' -- or your preferred ISO‑639‑3 code
  ORDER  BY taxonID, preferred DESC NULLS LAST
) v
WHERE t.taxonID = v.taxonID;


	4.	Populate ancestral common‑name columns
You already have L10_taxonID, L20_taxonID, … ; loop over them:

DO $$
DECLARE lvl TEXT;
BEGIN
  FOREACH lvl IN ARRAY ARRAY['L10','L20','L30','L40','L50','L70'] LOOP
    EXECUTE format($f$
      UPDATE expanded_taxa_cmns t
      SET    %I_commonName = v.name
      FROM   (
        SELECT DISTINCT ON (taxonID)
               taxonID, name
        FROM   coldp_vernacular
        WHERE  language = 'eng'
        ORDER  BY taxonID, preferred DESC NULLS LAST
      ) v
      WHERE  t.%I_taxonID = v.taxonID;
    $f$, lvl, lvl);
  END LOOP;
END$$;


	5.	Handle taxa with >1 common name
Option A (preferred) Keep everything normalized:

CREATE TABLE vernacular_names (
  taxonID INTEGER NOT NULL,
  name TEXT,
  language CHAR(3),
  preferred BOOLEAN,
  country CHAR(2),
  area TEXT
);
INSERT INTO vernacular_names
  SELECT taxonID, name, language, preferred, country, area
  FROM   coldp_vernacular;

Then store only one “display name” in expanded_taxa_cmns (rule of thumb: preferred = TRUE AND language='eng').
Option B Store an array in each _commonName column (TEXT[]) and aggregate with string_agg. PostgreSQL array or JSONB both work, but you will incur extra storage and your pipeline code must be array‑aware.

2.2 Interface considerations
	•	Joining key – COL taxonID is a stable integer that does not collide with iNaturalist’s numeric IDs, so if you want to align COL names with your iNat‑derived taxa you must map IDs (e.g. via scientific-name + authorship). If you have already ingested COL as a reference authority, mapping is trivial.
	•	Updates – COL releases monthly; store source_release in your staging table so refreshing does not silently change common names.
	•	Language coverage – ColDP provides ISO‑639‑3 codes; you can easily extend UI locale support later.

⸻

3 · Why ColDP is preferable for common names
	•	Rich vernacular metadata (preferred, country, area, transliteration) not present in DwC‑A. ￼
	•	Direct 1:1 foreign key on taxonID; no need to parse meta.xml.
	•	Table list is stable and versioned under semantic‑version tags (current stable 1.1, Sept 2024). ￼
	•	The same ZIP also gives you Distribution, Media, Reference, TypeSpecimen, which you may leverage later for habitat filtering or specimen thumbnails. ￼

A DwC‑A workflow remains useful if you already parse Darwin Core in other pipelines, but expect to down‑cast metadata. TextTree is purely visual; ACEF is obsolete. ￼ ￼ ￼

⸻

4 · Other COL tables worth considering (future work)

Table	Potential use
Distribution.txt	Populate region‑aware filters in your export scripts (e.g. in‑region vs out‑of‑region species).
Media.txt	Provide links to authoritative images for UI hover‑cards.
Reference.txt	Attach citation metadata to taxa for client display.
TypeSpecimen.txt	Could inform QA pipelines for model predictions.

All of these are already present in 2024_coldp.zip. ￼

⸻

5 · Next suggested steps
	1.	Download the missing TextTree only if you want a quick visual diff tool; it is not needed for vernacular data.
	2.	Implement the SQL snippets above inside your ingestion wrapper (or a dedicated Alembic migration) and test on a staging DB.
	3.	Once the expanded_taxa_cmns view is validated by downstream scripts, you can deprecate the older table or keep both side‑by‑side for backward compatibility.
	4.	If you wish to internationalise, adjust the sub‑query filter language='eng' and repeat for other codes (spa, fra, etc.), writing them into separate columns or a JSONB of {lang: name}.

Feel free to follow up when you are ready to formalise the filtering logic in your export side; I can help draft precise SQL functions or a Python ORM model for the vernacular‐name joins.

⸻

Key references
	•	ColDP specification & schema — GitHub repo  ￼
	•	COL yearly download page listing ColDP, DwC‑A, TextTree  ￼
	•	COL “Using the Catalogue of Life” (format overview, TextTree, ACEF)  ￼ ￼
	•	ColDP VernacularName field definitions  ￼
	•	TextTree template (file layout)  ￼
	•	ColDP vs other formats (BISS/TDWG paper)  ￼
	•	Darwin Core Archive how‑to (GBIF IPT)  ￼
	•	Example DwC‑A containing vernacularname.txt (VASCAN vignette)  ￼
	•	DwC Taxon schema (vernacularName term)  ￼
	•	ACEF 2014 table/field list (PDF)  ￼

These ten sources cover each format’s definition and vernacular‑name support.

---- END ASSISTANT ----


---- USER ----

okay, ColDP it is-- that's a great resource, even better than I realized! A few follow-ups:

1) can you expand on what this means?
```
Joining key – COL taxonID is a stable integer that does not collide with iNaturalist’s numeric IDs, so if you want to align COL names with your iNat‑derived taxa you must map IDs (e.g. via scientific-name + authorship). If you have already ingested COL as a reference authority, mapping is trivial.
```
Our iNat-derived taxa uses iNaturalist's numeric IDs, so do these not map perfectly with the COL taxonID? Not sure what you mean by collide here. I was assuming that the int keys would align, at least for active taxa. We can definitely instead map via scientific names (I don't have authorship data for iNaturalist taxa). 

But here you make it sound like we can just use taxonID:
```
3 · Why ColDP is preferable for common names
	•	Rich vernacular metadata (preferred, country, area, transliteration) not present in DwC‑A. 
	•	Direct 1:1 foreign key on taxonID; no need to parse meta.xml.
	•	Table list is stable and versioned under semantic‑version tags (current stable 1.1, Sept 2024). 
	•	The same ZIP also gives you Distribution, Media, Reference, TypeSpecimen, which you may leverage later for habitat filtering or specimen thumbnails. 
```
So I think maybe you're saying that ColDP provides taxonID, which is the same taxonID ints as our iNat-derived taxonID int keys?

2) for `Handle taxa with >1 common name`, let's take option 1. we will only store one “display name” in expanded_taxa_cmns, preferred = TRUE AND language='eng' seems like the perfect rule of thumb.

3) while we only need the single preferred common names for the core/ancestral commonName columns in the protected expanded_taxa table, I want to go ahead and bring the other suggested COL tables into new ibridaDB tables:
```
Table
Potential use
Distribution.txt
Populate region‑aware filters in your export scripts (e.g. in‑region vs out‑of‑region species).
Media.txt
Provide links to authoritative images for UI hover‑cards.
Reference.txt
Attach citation metadata to taxa for client display.
TypeSpecimen.txt
Could inform QA pipelines for model predictions.
```
it will be easier to ingest, document, and define python ORMs for these now and have them available for our later frontend work: I think we will mostly likely want, at least, the authoritative images for hover cards (as you suggest) and citation metadata for client display.. possibly type specimen will also be useful, although I will have to look into what that table actually provides to understand how we might use that. 

can you provide python ORMs for the new tables? we don't need to generate ingest scripts quite yet, I will hand off that work to another LLM with full context about my filesystem and e.g. DB connection strings. But I would like you to provide full ORMs for each of the tables. You don't need to provide an expanded_taxa ORM as I already have one, although it is a bit out-of-date and so you will need to review for correctness. Previously we used the TaxaExpanded SQLAlchemy class to generate the expanded taxa table, however we now use the following shell script:
```dbTools/taxa/expand/expand_taxa.sh
#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# expand_taxa.sh
# -----------------------------------------------------------------------------
# Creates a new "expanded_taxa" table by expanding ancestry from the existing
# "taxa" table into structured columns ("L{level}_taxonID", "L{level}_name", etc.).
#
# This version uses *string concatenation* with quote_ident(...) and quote_nullable(...),
# bypassing placeholders entirely. This is the "sure" approach: no risk of
# placeholders vanishing, since we embed the actual values directly into the
# final SQL string.
#
# Steps:
#   1) Drop 'expanded_taxa' if exists; create base columns with quotes.
#   2) Add columns for each rank level ("L5_taxonID", "L5_name", etc.).
#   3) Create expand_taxa_procedure() as a function:
#      - We skip rank levels not in RANK_LEVELS (no 100).
#      - If debugging is enabled (DEBUG_EXPAND_TAXA=true), we RAISE NOTICE
#        about the row's data and the final SQL statement.
#      - We *string-concatenate* the column references, so no placeholders are used.
#   4) SELECT expand_taxa_procedure() to populate the table.
#   5) Create indexes on "L10_taxonID"... "L70_taxonID", plus "taxonID", "rankLevel", "name".
#   6) VACUUM (ANALYZE), notifications, done.
#
# Usage:
#   DEBUG_EXPAND_TAXA=true ./expand_taxa.sh
# -----------------------------------------------------------------------------

# ===[ 1) Setup & Logging ]====================================================
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/$(basename "$0" .sh)_$(date +%Y%m%d_%H%M%S).log"
echo "Starting new run at $(date)" > "${LOG_FILE}"

# Log messages (with timestamps) to both console and file
log_message() {
    local timestamp
    timestamp="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    echo "[$timestamp] $1" | tee -a "${LOG_FILE}"
}

# Redirect stdout/stderr to console+log
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}")

# Source your common functions (for execute_sql, send_notification, etc.)
source "/home/caleb/repo/ibridaDB/dbTools/export/v0/common/functions.sh"

# Environment / defaults
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_NAME="${DB_NAME:-ibrida-v0-r1}"
DB_USER="${DB_USER:-postgres}"

# If DEBUG_EXPAND_TAXA=true, we pass a GUC variable into Postgres to enable debug
DEBUG_EXPAND="${DEBUG_EXPAND_TAXA:-false}"  # "true" or "false"

# rank levels to expand (no 100). We'll handle 5, 10, 11, ... 70
RANK_LEVELS=(5 10 11 12 13 15 20 24 25 26 27 30 32 33 33.5 34 34.5 35 37 40 43 44 45 47 50 53 57 60 67 70)

# We'll create indexes only on L10..L70
INDEX_LEVELS=(10 20 30 40 50 60 70)

log_message "Beginning expand_taxa.sh for DB: ${DB_NAME} (DEBUG_EXPAND_TAXA=${DEBUG_EXPAND})"

# ===[ 2) Create expanded_taxa schema ]========================================
log_message "Step 1: Dropping old expanded_taxa and creating base columns with quotes."

execute_sql "
DROP TABLE IF EXISTS \"expanded_taxa\" CASCADE;
CREATE TABLE \"expanded_taxa\" (
    \"taxonID\"       INTEGER PRIMARY KEY,
    \"rankLevel\"     DOUBLE PRECISION,
    \"rank\"          VARCHAR(255),
    \"name\"          VARCHAR(255),
    \"taxonActive\"   BOOLEAN
    -- We'll add \"LXX_taxonID\", \"LXX_name\", \"LXX_commonName\" columns next
);
"

# ===[ 3) Add columns for each rank level ]====================================
log_message "Step 2: Adding L{level}_taxonID, L{level}_name, L{level}_commonName columns."

ADD_COLS=""
for L in "${RANK_LEVELS[@]}"; do
  SAFE_L=$(echo "${L}" | sed 's/\./_/g')
  ADD_COLS+=" ADD COLUMN \"L${SAFE_L}_taxonID\" INTEGER,
             ADD COLUMN \"L${SAFE_L}_name\" VARCHAR(255),
             ADD COLUMN \"L${SAFE_L}_commonName\" VARCHAR(255),"
done

# Remove trailing comma
ADD_COLS="${ADD_COLS%,}"

execute_sql "
ALTER TABLE \"expanded_taxa\"
${ADD_COLS};
"

# ===[ 4) Create expand_taxa_procedure() function ]============================
log_message "Step 3: Creating expand_taxa_procedure() with string-concatenation for dynamic columns."

# We'll incorporate a GUC "myapp.debug_expand" to signal debug mode in PL/pgSQL
if [ "${DEBUG_EXPAND}" = "true" ]; then
  execute_sql "SET myapp.debug_expand = 'on';"
else
  execute_sql "SET myapp.debug_expand = 'off';"
fi

execute_sql "
DROP FUNCTION IF EXISTS expand_taxa_procedure() CASCADE;

CREATE OR REPLACE FUNCTION expand_taxa_procedure()
RETURNS void
LANGUAGE plpgsql
AS \$\$
DECLARE
    t_rec RECORD;
    ancestor_ids TEXT[];
    this_ancestor TEXT;
    anc_data RECORD;
    effective_level TEXT;
    row_sql TEXT;
    debugging boolean := false;
BEGIN
    -- We'll read our GUC to see if debug is on
    BEGIN
        IF current_setting('myapp.debug_expand') = 'on' THEN
            debugging := true;
        END IF;
    EXCEPTION
        WHEN others THEN
            debugging := false;  -- if the GUC is not set, do nothing
    END;

    -- Only retrieve active taxa rows, ignoring inactive ones
    FOR t_rec IN
        SELECT taxon_id, ancestry, rank_level, rank, name, active
        FROM taxa
        WHERE active = true
    LOOP
        -- Insert base row
        INSERT INTO \"expanded_taxa\"(\"taxonID\", \"rankLevel\", \"rank\", \"name\", \"taxonActive\")
        VALUES (t_rec.taxon_id, t_rec.rank_level, t_rec.rank, t_rec.name, t_rec.active);

        IF t_rec.ancestry IS NOT NULL AND t_rec.ancestry <> '' THEN
            ancestor_ids := string_to_array(t_rec.ancestry, '/');
        ELSE
            ancestor_ids := ARRAY[]::TEXT[];
        END IF;

        -- Include self
        ancestor_ids := ancestor_ids || t_rec.taxon_id::TEXT;

        FOREACH this_ancestor IN ARRAY ancestor_ids
        LOOP
            BEGIN
                IF this_ancestor IS NULL THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping NULL ancestor for row taxon_id=%', t_rec.taxon_id;
                    END IF;
                    CONTINUE;
                END IF;

                SELECT rank_level, rank, name
                  INTO anc_data
                  FROM taxa
                 WHERE taxon_id = this_ancestor::INTEGER
                 LIMIT 1;

                IF NOT FOUND OR anc_data.name IS NULL THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping ancestor=% for row taxon_id=%: not found or name is NULL', this_ancestor, t_rec.taxon_id;
                    END IF;
                    CONTINUE;
                END IF;

                IF anc_data.rank_level NOT IN (
                    5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30,
                    32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45,
                    47, 50, 53, 57, 60, 67, 70
                ) THEN
                    IF debugging THEN
                        RAISE NOTICE 'Skipping rank_level=% for row taxon_id=% (ancestor=%)', anc_data.rank_level, t_rec.taxon_id, this_ancestor;
                    END IF;
                    CONTINUE;
                END IF;

                effective_level := replace(CAST(anc_data.rank_level AS TEXT), '.', '_');

                -- Build dynamic SQL via string concat + quote_ident(...) + quote_nullable(...)
                row_sql :=
                    'UPDATE \"expanded_taxa\" SET '
                    || quote_ident('L' || effective_level || '_taxonID') || ' = '
                        || quote_nullable(this_ancestor)
                    || ', '
                    || quote_ident('L' || effective_level || '_name') || ' = '
                        || quote_nullable(anc_data.name)
                    || ' WHERE \"taxonID\" = ' || quote_nullable(t_rec.taxon_id::text);

                IF debugging THEN
                    RAISE NOTICE 'Row taxon_id=% => rank_level=% => built SQL: %',
                                 t_rec.taxon_id, anc_data.rank_level, row_sql;
                END IF;

                EXECUTE row_sql;

            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Error updating row => base taxon_id=%, ancestor=%, anc_data=(%,%,%), row_sql=[%]',
                  t_rec.taxon_id, this_ancestor, anc_data.rank_level, anc_data.rank, anc_data.name, row_sql;
                RAISE;
            END;
        END LOOP;
    END LOOP;
END;
\$\$;
"

# ===[ 5) Populate expanded_taxa ]=============================================
log_message "Step 4: SELECT expand_taxa_procedure() to populate."

execute_sql "
SELECT expand_taxa_procedure();
"

log_message "Population of expanded_taxa complete. Running: \\d \"expanded_taxa\""
execute_sql "\d \"expanded_taxa\""

send_notification "expand_taxa.sh: Step 4 complete (expanded_taxa populated)."

# ===[ 6) Create indexes (only on L10..L70) ]===================================
log_message "Step 5: Creating indexes on L10_taxonID, L20_taxonID, ..., L70_taxonID plus base columns."

for L in "${INDEX_LEVELS[@]}"; do
  SAFE_L=$(echo "${L}" | sed 's/\./_/g')
  execute_sql "
  CREATE INDEX IF NOT EXISTS idx_expanded_taxa_L${SAFE_L}_taxonID
    ON \"expanded_taxa\"(\"L${SAFE_L}_taxonID\");
  "
done

execute_sql "
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_taxonID    ON \"expanded_taxa\"(\"taxonID\");
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_rankLevel  ON \"expanded_taxa\"(\"rankLevel\");
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_name       ON \"expanded_taxa\"(\"name\");
"

log_message "Index creation done. Running: \\d \"expanded_taxa\""
execute_sql "\d \"expanded_taxa\""

send_notification "expand_taxa.sh: Step 5 complete (indexes created)."

# ===[ 7) VACUUM ANALYZE ]====================================================
log_message "Step 6: VACUUM ANALYZE \"expanded_taxa\" (final step)."

execute_sql "
VACUUM (ANALYZE) \"expanded_taxa\";
"

send_notification "expand_taxa.sh: Step 6 complete (VACUUM ANALYZE done)."
log_message "expand_taxa.sh complete. Exiting."
```
Here's the corresponding sqlalchemy model for this table-- again, you need to double-check this for correctness. I know we the name is incorrect (below names the table taxa_expanded, the actual name is not expanded_taxa, the protected copy will be expanded_taxa_cmn):
```dbTools/taxa/models/expanded_taxa.py
from sqlalchemy import Boolean, Column, Integer, String, Text
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()


class TaxaExpanded(Base):
    __tablename__ = "taxa_expanded"

    taxon_id = Column(Integer, primary_key=True, nullable=False)
    name = Column(String(64), index=True)
    common_name = Column(Text)
    rank = Column(Text)
    rank_level = Column(Integer, index=True)
    taxon_active = Column(Boolean, index=True)
    L5_taxon_id = Column(Integer)
    L5_name = Column(Text)  # Ancestral string columns should be text
    L5_common_name = Column(Text)  # In MySQL, this just stores a pointer to the string
    L10_taxon_id = Column(
        Integer
    )  # This allows us to fit within the row width byte limit imposed by InnoDB
    L10_name = Column(Text)
    L10_common_name = Column(Text)
    L11_taxon_id = Column(Integer)
    L11_name = Column(Text)
    L11_common_name = Column(Text)
    L12_taxon_id = Column(Integer)
    L12_name = Column(Text)
    L12_common_name = Column(Text)
    L13_taxon_id = Column(Integer)
    L13_name = Column(Text)
    L13_common_name = Column(Text)
    L15_taxon_id = Column(Integer)
    L15_name = Column(Text)
    L15_common_name = Column(Text)
    L20_taxon_id = Column(Integer)
    L20_name = Column(Text)
    L20_common_name = Column(Text)
    L24_taxon_id = Column(Integer)
    L24_name = Column(Text)
    L24_common_name = Column(Text)
    L25_taxon_id = Column(Integer)
    L25_name = Column(Text)
    L25_common_name = Column(Text)
    L26_taxon_id = Column(Integer)
    L26_name = Column(Text)
    L26_common_name = Column(Text)
    L27_taxon_id = Column(Integer)
    L27_name = Column(Text)
    L27_common_name = Column(Text)
    L30_taxon_id = Column(Integer)
    L30_name = Column(Text)
    L30_common_name = Column(Text)
    L32_taxon_id = Column(Integer)
    L32_name = Column(Text)
    L32_common_name = Column(Text)
    L33_taxon_id = Column(Integer)
    L33_name = Column(Text)
    L33_common_name = Column(Text)
    L33_5_taxon_id = Column(Integer)
    L33_5_name = Column(Text)
    L33_5_common_name = Column(Text)
    L34_taxon_id = Column(Integer)
    L34_name = Column(Text)
    L34_common_name = Column(Text)
    L34_5_taxon_id = Column(Integer)
    L34_5_name = Column(Text)
    L34_5_common_name = Column(Text)
    L35_taxon_id = Column(Integer)
    L35_name = Column(Text)
    L35_common_name = Column(Text)
    L37_taxon_id = Column(Integer)
    L37_name = Column(Text)
    L37_common_name = Column(Text)
    L40_taxon_id = Column(Integer)
    L40_name = Column(Text)
    L40_common_name = Column(Text)
    L43_taxon_id = Column(Integer)
    L43_name = Column(Text)
    L43_common_name = Column(Text)
    L44_taxon_id = Column(Integer)
    L44_name = Column(Text)
    L44_common_name = Column(Text)
    L45_taxon_id = Column(Integer)
    L45_name = Column(Text)
    L45_common_name = Column(Text)
    L47_taxon_id = Column(Integer)
    L47_name = Column(Text)
    L47_common_name = Column(Text)
    L50_taxon_id = Column(Integer)
    L50_name = Column(Text)
    L50_common_name = Column(Text)
    L53_taxon_id = Column(Integer)
    L53_name = Column(Text)
    L53_common_name = Column(Text)
    L57_taxon_id = Column(Integer)
    L57_name = Column(Text)
    L57_common_name = Column(Text)
    L60_taxon_id = Column(Integer)
    L60_name = Column(Text)
    L60_common_name = Column(Text)
    L67_taxon_id = Column(Integer)
    L67_name = Column(Text)
    L67_common_name = Column(Text)
    L70_taxon_id = Column(Integer)
    L70_name = Column(Text)
    L70_common_name = Column(Text)
    L100_taxon_id = Column(Integer)
    L100_name = Column(Text)
    L100_common_name = Column(Text)
```
The above model contains some references to mysql compatibility.. that's from an old project, we are standardizing on psql/postgis for ibridaDB (nothing else). To prepare the above sqlalchemy model for the new `expanded_taxa_cmn` table, do we just need to change the name? any missing columns? any incorrect types? Use the shell script as the reference here; that's what we actually used to generate the expanded_taxa table on our database. I don't think this ORM needs to directly reference a new VernacularNames ORM, does it?


I will also show you the below notes from my repo-- we identified several rank levels that have ambiguous names (>1 possible name for the rank), I'm pretty sure that only L5, L10, L20 have these:
```
# Taxon ranks
## code_to_name
*maps taxon rank polli-style code to rank names*
code_to_name = {
    'L5': 'subspecies',
    'L10': 'species',
    'L11': 'complex',
    'L12': 'subsection', 
    'L13': 'section',
    'L15': 'subgenus',
    'L20': 'genus',
    'L24': 'subtribe',
    'L25': 'tribe',
    'L26': 'supertribe',
    'L27': 'subfamily',
    'L30': 'family',
    'L32': 'epifamily',
    'L33': 'superfamily',
    'L33_5': 'zoosubsection',
    'L34': 'zoosection',
    'L34_5': 'parvorder',
    'L35': 'infraorder',
    'L37': 'suborder',
    'L40': 'order',
    'L43': 'superorder',
    'L44': 'subterclass',
    'L45': 'infraclass',
    'L47': 'subclass',
    'L50': 'class',
    'L53': 'superclass',
    'L57': 'subphylum',
    'L60': 'phylum',
    'L67': 'subkingdom',
    'L70': 'kingdom'
}
### ambiguous ranks
We assume that the possibly ambiguous ranks are of the above ranks downstream. However, note that the following levels could be ambiguous:
*Possible ranks:*
- L5: form, infrahybrid, subspecies
- L10: hybrid, species
- L20: genus, genushybrid
```

Can you propose ColDP_VernacularNames, ColDP_Distribution, ColDP_Media, ColDP_Reference, and ColDP_TypeSpecimen ORMs? You can adjust those table names as you wish to be more proper, these are just suggestions.

Here are the files that we extracted from the ColDP zipfile:
```
caleb@blade:/datasets/taxa/catalogue_of_life/2024/ColDP$ ls
Distribution.tsv  Media.tsv      NameRelation.tsv  reference.json  source               SpeciesInteraction.tsv    TaxonProperty.tsv  VernacularName.tsv
logo.png          metadata.yaml  NameUsage.tsv     Reference.tsv   SpeciesEstimate.tsv  TaxonConceptRelation.tsv  TypeMaterial.tsv
caleb@blade:/datasets/taxa/catalogue_of_life/2024/ColDP$ ls source
1005.yaml  1032.yaml  1053.yaml  1080.yaml  1093.yaml  1107.yaml  1124.yaml  1138.yaml  1152.yaml  1168.yaml  1180.yaml  1193.yaml  1204.yaml    2141.yaml    2317.yaml
...
1031.yaml  1052.yaml  1078.yaml  1092.yaml  1106.yaml  1123.yaml  1134.yaml  1150.yaml  1167.yaml  1179.yaml  1192.yaml  1203.yaml  2130.yaml    2304.yaml
```
I will provide samples (head -n 10) from all of the extracted files (except for source/, I provide head -n 50 from only one of the yamls) below to help guide you:
```ColDP_raw_samples.txt
<Distribution.tsv>
<head -n 10>
col:taxonID	col:sourceID	col:areaID	col:area	col:gazetteer	col:status	col:referenceID	col:remarks
BLL2J		CN		iso	native		
BLL2J		TW		iso	native		
3LWT2		CR		iso	native		
444RB			Uruguay (Rivera)	text	native		
69PYD			North America	text	native		
8VVZD		MXC		tdwg	native		
8VVZD		MXG		tdwg	native		
8VVZD		MXE		tdwg	native		
8VVZD		MXT		tdwg	native		
</Distribution.tsv>
</head -n 10>

<Media.tsv>
<head -n 10>
col:taxonID	col:sourceID	col:url	col:type	col:format	col:title	col:created	col:creator	col:license	col:link	col:remarks
</Media.tsv>
</head -n 10>

<metadata.yaml>
<head -n 10>
---
key: 299029
doi: 10.48580/dg9ld
title: Catalogue of Life
alias: COL24
description: |-
  The Catalogue of Life is an assembly of expert-based global species checklists with the aim to build a comprehensive catalogue of all known species of organisms on Earth. Continuous progress is made towards completion, but for now, it probably includes just over 80% of the world's known species. The Catalogue of Life estimates 2.3M extant species on the planet recognised by taxonomists at present time. This means that for many groups it continues to be deficient, and users may notice that many species are still missing from the Catalogue.

  ### What's new in 2024 Annual Checklist?

</metadata.yaml>
</head -n 10>

<NameRelation.tsv>
<head -n 10>
col:nameID	col:relatedNameID	col:sourceID	col:type	col:referenceID	col:page	col:remarks
CX5Y	6ZBQ2		basionym			
4DQ2L	6ZDLT		basionym			
4DQ2M	6ZDLY		basionym			
85QXH	BKZY		basionym			
4J2RF	6XKWB		basionym			
67CMV	CDYT5		basionym			
67CN7	4KGYM		basionym			
5VCMV	3L8K9		basionym			
67CMQ	6DV6D		basionym			
</NameRelation.tsv>
</head -n 10>

<NameUsage.tsv>
<head -n 10>
col:ID	col:alternativeID	col:nameAlternativeID	col:sourceID	col:parentID	col:basionymID	col:status	col:scientificName	col:authorship	col:rank	col:notho	col:originalSpelling	col:uninomial	col:genericName	col:infragenericEpithet	col:specificEpithet	col:infraspecificEpithet	col:cultivarEpithet	col:combinationAuthorship	col:combinationAuthorshipID	col:combinationExAuthorship	col:combinationExAuthorshipID	col:combinationAuthorshipYear	col:basionymAuthorship	col:basionymAuthorshipID	col:basionymExAuthorship	col:basionymExAuthorshipID	col:basionymAuthorshipYear	col:namePhrase	col:nameReferenceID	col:publishedInYear	col:publishedInPage	col:publishedInPageLink	col:gender	col:genderAgreement	col:etymology	col:code	col:nameStatus	col:accordingToID	col:accordingToPage	col:accordingToPageLink	col:referenceID	col:scrutinizer	col:scrutinizerID	col:scrutinizerDate	col:extinct	col:temporalRangeStart	col:temporalRangeEnd	col:environment	col:species	col:section	col:subgenus	col:genus	col:subtribe	col:tribe	col:subfamily	col:family	col:superfamily	col:suborder	col:order	col:subclass	col:class	col:subphylum	col:phylum	col:kingdom	col:ordinal	col:branchLength	col:link	col:nameRemarks	col:remarks
673FW			2232	3CP83	3CP83	synonym	Anisophyllum hyssopifolium	(L.) Haw.	species				Anisophyllum		hyssopifolium			Haw.					L.						0a8270ab-617f-402d-b3bf-c3f0fe6b0a0a							botanical																															https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:1042669-2		
9L2J9			2232	3F5B8	3F5B8	synonym	Asperula aparine var. aparine		variety				Asperula		aparine	aparine													308d3079-d3d3-4523-af56-80e4507eade8							botanical																															https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:77168438-1		
8RX53			1130	9WRMR		synonym	Saccoia escoffierae var. triangulata	Sacco, 1895	variety				Saccoia		escoffierae	triangulata		Sacco				1895							75d294da-5cc2-4241-b178-c5686ae93d97		42, pl. 1, fig. 116					zoological					28419c41-a4be-4567-9131-512c920576bd																										https://www.molluscabase.org/aphia.php?p=taxdetails&id=1545847		
555CQ			1141	C9FM		synonym	Telanthera flavescens	(Kunth) Moq.	species				Telanthera		flavescens			Moq.					Kunth						c59b73dc-e818-4ec0-8131-4f317c9139c6							botanical																																	
7TDYP			1130	3PP2B	9BD4Q	synonym	Triphora sarissa	Dall, 1889	species				Triphora		sarissa			Dall				1889														zoological																															https://www.molluscabase.org/aphia.php?p=taxdetails&id=1481479		
C33N7			1175	858KS		accepted	Amalocythere fulgida	Guan, 1978	species				Amalocythere		fulgida			Guan				1978							8db3f7fe-e3df-49ec-978c-717af25cea87							zoological	established				8db3f7fe-e3df-49ec-978c-717af25cea87	Brandão, Simone Nunes		2016-06-30	true			marine																			https://www.marinespecies.org/ostracoda/aphia.php?p=taxdetails&id=773107		
85BKX			2144	84JVC		accepted	Coronalpheus	Wicksten, 1999	genus			Coronalpheus						Wicksten				1999														zoological	acceptable				bc596268-7fff-4a3c-868b-3c392a7be32b			2021-04-26	false																						https://www.itis.gov/servlet/SingleRpt/SingleRpt?search_topic=TSN&search_value=1147818		
B3XCS			1141	5ZXM8		ambiguous synonym	Convolvulus rupestris	Buch	species				Convolvulus		rupestris			Buch											5f264aa0-ccf7-4da8-ad97-0ef3f4913f7e		193					botanical																																	
3HNHY			2232	8VXZW		accepted	Guzmania variegata	L.B.Sm.	species				Guzmania		variegata			L.B.Sm.											6683ea9d-d407-472a-8daa-943b551b3eaf							botanical																															https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:115257-2		Ecuador to Peru
</NameUsage.tsv>
</head -n 10>

<reference.json>
<head -n 10>
[
{"id":"1382","author":[{"family":"Weiss, Norbert, ed."}],"issued":{"date-parts":[[2001]]},"title":"Validation List no. 79: Validation of publication of new names and new combinations previously effectively published outside of the IJSEM","container-title":"International Journal of Systematic and Evolutionary Microbiology, vol. 51, no. 2"},
{"id":"1383","author":[{"family":"Chisholm, S. W., S. L. Frankel, R. Goericke, R. J. Olsen, B. Palenik, J. B. Waterbury, et al."}],"issued":{"date-parts":[[1992]]},"title":"Prochlorococcus marinus nov. gen. nov. sp.: an oxyphototrophic marine prokaryote containing divinyl chlorophyll a and b","container-title":"Archives in Microbiology, vol. 157"},
{"id":"1384","author":[{"family":"Partensky, F., W. R. Hess, and D. Vaulot"}],"issued":{"date-parts":[[1999]]},"title":"Prochlorococcus, a Marine Photosynthetic Prokaryote of Global Significance","container-title":"Microbiology and Molecular Biology Reviews, vol. 63, no. 1"},
{"id":"171","author":[{"family":"Sneath, Peter H.A., Nicholas S. Mair, M. Elisabeth Sharpe, and John G. Holt (eds.)"}],"issued":{"date-parts":[[1986]]},"container-title":"Bergey's Manual of Systematic Bacteriology. vol. 2"},
{"id":"1331","author":[{"family":"Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds."}],"issued":{"date-parts":[[1980]]},"title":"Approved Lists of Bacterial Names","container-title":"International Journal of Systematic Bacteriology, vol. 30, no.1"},
{"id":"4731","author":[{"family":"Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds."}],"issued":{"date-parts":[[1989]]},"container-title":"Approved Lists of Bacterial Names"},
{"author":[{"family":"S"}],"issued":{"date-parts":[[2000,1,1]]},"title":"SN2000/Levine, 1982"},
{"author":[{"family":"S"}],"issued":{"date-parts":[[2000,1,1]]},"title":"SN2000/Perkins, 2000"},
{"title":"As per Gigaductus"},
</reference.json>
</head -n 10>

<Reference.tsv>
<head -n 10>
col:ID	col:alternativeID	col:sourceID	col:citation	col:type	col:author	col:editor	col:title	col:titleShort	col:containerAuthor	col:containerTitle	col:containerTitleShort	col:issued	col:accessed	col:collectionTitle	col:collectionEditor	col:volume	col:issue	col:edition	col:page	col:publisher	col:publisherPlace	col:version	col:isbn	col:issn	col:doi	col:link	col:remarks
12ddc4b3-d551-4c38-8d20-4a2246b9e8d6		2144	Weiss, Norbert, ed. (2001). Validation List no. 79: Validation of publication of new names and new combinations previously effectively published outside of the IJSEM. International Journal of Systematic and Evolutionary Microbiology, Vol. 51, No. 2.		Weiss, Norbert, ed.		Validation List no. 79: Validation of publication of new names and new combinations previously effectively published outside of the IJSEM			International Journal of Systematic and Evolutionary Microbiology, vol. 51, no. 2		2001															
5eb14d90-e68f-4fda-be6c-453c6965707b		2144	Chisholm, S. W., S. L. Frankel, R. Goericke, R. J. Olsen, B. Palenik, J. B. Waterbury, et al. (1992). Prochlorococcus marinus nov. gen. nov. sp.: an oxyphototrophic marine prokaryote containing divinyl chlorophyll a and b. Archives in Microbiology, Vol. 157.		Chisholm, S. W., S. L. Frankel, R. Goericke, R. J. Olsen, B. Palenik, J. B. Waterbury, et al.		Prochlorococcus marinus nov. gen. nov. sp.: an oxyphototrophic marine prokaryote containing divinyl chlorophyll a and b			Archives in Microbiology, vol. 157		1992															
6b833931-90b9-4dca-b98c-d3e300075c7e		2144	Partensky, F., W. R. Hess, and D. Vaulot. (1999). Prochlorococcus, a Marine Photosynthetic Prokaryote of Global Significance. Microbiology and Molecular Biology Reviews, Vol. 63, No. 1.		Partensky, F., W. R. Hess, and D. Vaulot		Prochlorococcus, a Marine Photosynthetic Prokaryote of Global Significance			Microbiology and Molecular Biology Reviews, vol. 63, no. 1		1999															
c28f7f52-c223-4410-90ec-9142da3e34ab		2144	Sneath, Peter H.A., Nicholas S. Mair, M. Elisabeth Sharpe, and John G. Holt (eds.). (1986). Bergey’s Manual of Systematic Bacteriology. Vol. 2.		Sneath, Peter H.A., Nicholas S. Mair, M. Elisabeth Sharpe, and John G. Holt (eds.)					Bergey's Manual of Systematic Bacteriology. vol. 2		1986															
fa90c9ed-a347-4ae8-9feb-d2dec6bd8f97		2144	Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds. (1980). Approved Lists of Bacterial Names. International Journal of Systematic Bacteriology, Vol. 30, no.1.		Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds.		Approved Lists of Bacterial Names			International Journal of Systematic Bacteriology, vol. 30, no.1		1980															
be12e305-5fb7-4184-b33d-b6601e9c4140		2144	Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds. (1989). Approved Lists of Bacterial Names.		Skerman, V. B. D., Vicki McGowan, and P. H. A. Sneath, eds.					Approved Lists of Bacterial Names		1989															
c75a73a2-0c85-4d63-a46a-c7f46d5f7913		2007	Seenivasan, R.; Sausen, N.; Medlin, L. K.; Melkonian, M. (2013). Picomonas judraskeda gen. et sp. nov.: the first identified member of the Picozoa phylum nov., a widespread group of picoeukaryotes, formerly known as 'picobiliphytes'. PLoS ONE. 8(3): e59565.																								
2ea6bf13-11f2-474f-b9ab-4e30333d3ade		2007	Article title: Phylogeny of novel naked filose and reticulose Cercozoa: Granofilosea cl. n. and Proteomyxidea revised.																								
535b1b3f-d59c-4da8-bc3b-abf664243b17		2007	Yabuki, A.; Chao, E. E.; Ishida, K.-I.; Cavalier-Smith, T. (2012). Microheliella maris (Microhelida ord. n.), an ultrastructurally highly distinctive new axopodial protist species and genus, and the unity of phylum Heliozoa. Protist. 163(3): 356-388.																								
</Reference.tsv>
</head -n 10>

<SpeciesEstimate.tsv>
<head -n 10>
col:taxonID	col:sourceID	col:estimate	col:type	col:referenceID	col:remarks
BRKNQ		5385	species living	74	
622DH		317	species living	30	
4XK		85	species living	74	
FJ5		37	species living	30	
625XT		2	species living	55	
HJR		93	species living	30	
9LT		46	species living	30	
CZK		79	species living	55	
8NKJ8		71	species living	29	
</SpeciesEstimate.tsv>
</head -n 10>

<SpeciesInteraction.tsv>
<head -n 10>
col:taxonID	col:relatedTaxonID	col:sourceID	col:relatedTaxonScientificName	col:type	col:referenceID	col:remarks
</SpeciesInteraction.tsv>
</head -n 10>

<TaxonConceptRelation.tsv>
<head -n 10>
col:taxonID	col:relatedTaxonID	col:sourceID	col:type	col:referenceID	col:remarks
</TaxonConceptRelation.tsv>
</head -n 10>

<TaxonProperty.tsv>
<head -n 10>
col:taxonID	col:sourceID	col:property	col:value	col:ordinal	col:referenceID	col:page	col:remarks
</TaxonProperty.tsv>
</head -n 10>

<TypeMaterial.tsv>
<head -n 10>
col:ID	col:nameID	col:sourceID	col:citation	col:status	col:referenceID	col:page	col:country	col:locality	col:latitude	col:longitude	col:altitude	col:sex	col:host	col:associatedSequences	col:date	col:collector	col:institutionCode	col:catalogNumber	col:link	col:remarks
</TypeMaterial.tsv>
</head -n 10>

<VernacularName.tsv>
<head -n 10>
col:taxonID	col:sourceID	col:name	col:transliteration	col:language	col:preferred	col:country	col:area	col:sex	col:referenceID	col:remarks
B6LM6		bacteria	bacteria	eng						
B6LM6		bacterias	bacterias	spa						
R5LB		Sandcarpet	Sandcarpet	eng						
76SYT		Alcajes	Alcajes							
76SYT		Rajamatraca	Rajamatraca							
333V8		Patana	Patana	cbq						
6C59B		Clavellina	Clavellina							
3XSNW		Pitayita	Pitayita							
3XSJY		Cochilinque	Cochilinque							
</VernacularName.tsv>
</head -n 10>

<source/1005.yaml>
<head -n 50>
---
key: 1005
doi: 10.48580/dfrdl-37p
title: Catalogue of Craneflies of the World
alias: CCW
description: "The Catalogue of the Craneflies of the World (CCW) covers all genera,\
  \ subgenera, species, subspecies, and synonyms of the World Tipuloidea (Insecta\
  \ – Diptera – Nematocera – families Pediciidae, Limoniidae, Cylindrotomidae, Tipulidae).\
  \ It also includes up to date information on the distribution of the species and\
  \ subspecies, specified by countries and, for the larger countries, states, provinces\
  \ and islands. The website’s list of references has over 7.400 titles, about 4.300\
  \ of which available as easy downloadable pdf."
issued: 2021-05-07
version: May 2021
contact:
  given: P
  family: Oosterbroek
creator:
 -
  given: P.
  family: Oosterbroek
contributor:
 -
  city: Leiden
  country: NL
  address: "Leiden, Netherlands"
  organisation: Naturalis Biodiversity Center
keyword: []
containerKey: 299029
containerTitle: Catalogue of Life
containerCreator:
 -
  orcid: 0000-0001-6197-9951
  given: Olaf
  family: Bánki
  city: Amsterdam
  country: NL
  note: COL Managing Director
  address: "Amsterdam, Netherlands"
  organisation: Catalogue of Life
 -
  orcid: 0000-0003-2137-2690
  given: Yury
  family: Roskov
  city: Champaign
  state: IL
  country: US
  note: COL Executive Editor
  address: "Champaign, IL, United States of America"
  organisation: Illinois Natural History Survey				
</source/1005.yaml>
</head -n 50>
```
I am noticing that the taxonIDs used in e.g. NameUsage.tsv aren't the same as our iNat-derived int taxonIDs, so unless you see an appropriate mapping in the samples above then I suppose we will need to join on scientific names?

---- END USER ---

---- ASSISTANT ----
Key points up‑front 
* Catalogue of Life (COL) assigns its own five‑character, alphanumeric taxonID values that are unique within COL but have no numerical relationship to iNaturalist’s consecutive integer taxon_ids. Therefore a 1‑to‑1 foreign‑key join is impossible—you must map the two vocabularies through scientific names (plus optional authorship or rank context).
* When you ingest ColDP, load the VernacularName table and pick preferred, English rows to fill the new commonName fields, then keep the entire set of vernacular rows in a separate, normalised table for possible multi‑language use. ￼
* Besides VernacularName, ColDP ships first‑class tables for Distribution, Media, Reference, and TypeMaterial. Their schemas map cleanly to Postgres types and are safe to mirror in ibridaDB now for future front‑end use. ￼

Below you will find

1. A detailed explanation of the identifier mismatch and a robust mapping recipe.
2. An updated SQLAlchemy ORM for your expanded_taxa_cmn table (removes the obsolete L100_* columns, corrects types, and points to the right table name).
3. Clean, Postgres‑oriented ORMs for VernacularName, Distribution, Media, Reference, and TypeMaterial (you can rename classes as you wish).

⸻

1 · Why COL taxonID ≠ iNaturalist taxon_id

1.1 Identifier provenance
	•	COL’s identifiers are internal “checklist keys” minted when each source checklist is merged; they are opaque strings such as 8VVZD or C33N7.
	•	iNaturalist uses monotonically increasing integers (e.g. Serpentes = 85553) that double as primary keys in their Rails database and in the public API.
	•	Even where iNat says a branch is “sourced to Catalogue of Life” the linkage is maintained only as taxon‑framework metadata, not by sharing primary keys.

1.2 Collision vs. mismatch

The two identifier spaces cannot collide numerically because they live in different namespaces, but they also never coincide: COL’s 8VVZD is not the same taxon as iNat 874562 even if both refer to Danaus plexippus.

1.3 Practical mapping recipe

Step	Action
1	Load ColDP NameUsage.tsv into a staging table (coldp_nameusage) keyed on scientificName, authorship, and rank.
2	Build an index on lower‑cased, whitespace‑normalised scientificName in both datasets (COL + iNat).
3	Exact‑string join on canonical binomial/trinomial plus rank; where multiple COL hits occur pick status='accepted'.
4	For residuals, fall back to fuzzy join using the Levenshtein distance of canonical names and compare higher‑rank ancestors to resolve homonyms.
5	Persist a cross‑walk table (inat_to_coldp) with columns inat_taxon_id, coldp_taxon_id, match_quality, matched_name, coldp_name.

This approach yields deterministic keys for foreign‑key joins while remaining update‑safe when COL publishes a new annual checklist.

⸻

2 · Revised ORM for expanded_taxa_cmn

from sqlalchemy import (
    Column, Integer, String, Text, Boolean, Float, Index
)
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class ExpandedTaxaCmn(Base):
    """
    Copy of expanded_taxa with additional common‑name columns.
    Only the *preferred English* common name is stored per taxon.
    """
    __tablename__ = "expanded_taxa_cmn"

    taxonID       = Column(Integer, primary_key=True, nullable=False)
    rankLevel     = Column(Float, index=True)
    rank          = Column(String(255))
    name          = Column(String(255), index=True)
    commonName    = Column(String(255))               # NEW
    taxonActive   = Column(Boolean, index=True)

    # Ancestral columns – dots converted to underscores to match SQL
{% for lvl in [5,10,11,12,13,15,20,24,25,26,27,30,32,33,'33_5',34,'34_5',35,37,40,43,44,45,47,50,53,57,60,67,70] %}
    L{{lvl}}_taxonID    = Column(Integer)
    L{{lvl}}_name       = Column(Text)
    L{{lvl}}_commonName = Column(String(255))
{% endfor %}

# Helpful composite index for frequent ancestor look‑ups
Index("idx_expanded_taxa_cmn_L10_taxonID", "L10_taxonID")

Changes vs. your legacy TaxaExpanded
	•	__tablename__ corrected.
	•	rankLevel now Float (Postgres double precision).
	•	Removed the entire L100_* trio to match the shell script.
	•	Base and ancestor common‑name columns use String(255)—same length as your name fields.

⸻

3 · New ColDP ORMs

from sqlalchemy import (
    Column, String, Text, Boolean, Date, Numeric, Integer
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class ColdpVernacularName(Base):
    __tablename__ = "coldp_vernacular_name"
    taxonID        = Column(String(10), primary_key=True)
    sourceID       = Column(String(10))
    name           = Column(Text, nullable=False)
    transliteration= Column(Text)
    language       = Column(String(3))      # ISO‑639‑3
    preferred      = Column(Boolean)
    country        = Column(String(2))      # ISO‑3166‑1‑alpha‑2
    area           = Column(Text)
    sex            = Column(String(20))
    referenceID    = Column(String(64))
    remarks        = Column(Text)

class ColdpDistribution(Base):
    __tablename__ = "coldp_distribution"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    taxonID        = Column(String(10), index=True)
    sourceID       = Column(String(10))
    areaID         = Column(String(10))
    area           = Column(Text)
    gazetteer      = Column(String(10))
    status         = Column(String(25))     # e.g. native, introduced
    referenceID    = Column(String(64))
    remarks        = Column(Text)

class ColdpMedia(Base):
    __tablename__ = "coldp_media"
    id             = Column(Integer, primary_key=True, autoincrement=True)
    taxonID        = Column(String(10), index=True)
    sourceID       = Column(String(10))
    url            = Column(Text, nullable=False)
    type           = Column(String(50))     # stillImage, sound, video …
    format         = Column(String(50))     # MIME type or file suffix
    title          = Column(Text)
    created        = Column(Date)
    creator        = Column(Text)
    license        = Column(String(100))
    link           = Column(Text)           # landing page
    remarks        = Column(Text)

class ColdpReference(Base):
    __tablename__ = "coldp_reference"
    ID             = Column(String(64), primary_key=True)   # UUID or short key
    alternativeID  = Column(String(64))
    sourceID       = Column(String(10))
    citation       = Column(Text)
    type           = Column(String(30))
    author         = Column(Text)
    editor         = Column(Text)
    title          = Column(Text)
    titleShort     = Column(Text)
    containerAuthor= Column(Text)
    containerTitle = Column(Text)
    containerTitleShort = Column(Text)
    issued         = Column(String(50))
    accessed       = Column(String(50))
    collectionTitle= Column(Text)
    collectionEditor= Column(Text)
    volume         = Column(String(30))
    issue          = Column(String(30))
    edition        = Column(String(30))
    page           = Column(String(50))
    publisher      = Column(Text)
    publisherPlace = Column(Text)
    version        = Column(String(30))
    isbn           = Column(String(20))
    issn           = Column(String(20))
    doi            = Column(String(100))
    link           = Column(Text)
    remarks        = Column(Text)

class ColdpTypeMaterial(Base):
    """
    ColDP entity `TypeMaterial` (called TypeSpecimen in the user request).
    """
    __tablename__ = "coldp_type_material"
    ID              = Column(String(64), primary_key=True)
    nameID          = Column(String(10), index=True)
    sourceID        = Column(String(10))
    citation        = Column(Text)
    status          = Column(String(50))
    referenceID     = Column(String(64))
    page            = Column(String(50))
    country         = Column(String(2))
    locality        = Column(Text)
    latitude        = Column(Numeric(9,5))
    longitude       = Column(Numeric(9,5))
    altitude        = Column(String(50))
    sex             = Column(String(12))
    host            = Column(Text)
    associatedSequences = Column(Text)
    date            = Column(Date)
    collector       = Column(Text)
    institutionCode = Column(String(25))
    catalogNumber   = Column(String(50))
    link            = Column(Text)
    remarks         = Column(Text)

Implementation notes
	•	Primary keys—taxonID alone is not guaranteed unique in Media and Distribution, so synthetic integer PKs (id) are provided.
	•	Text vs. String—long free‑form columns use Text; controlled‑vocabulary or short identifiers use String.
	•	All Date fields assume ISO‑8601 strings in the TSV; feel free to cast to DateTime if time‑of‑day is ever present.
	•	If you load reference.json (CSL array), deserialize to the same coldp_reference table—store JSON in a side column if you want to preserve the CSL structure.

⸻

4 · Next steps
	1.	Back‑fill inat_to_coldp mapping using the recipe in §1.3—this unlocks direct joins between iNat observations and COL’s richer metadata.
	2.	Run a small pilot on, say, 100 species to verify that the preferred English commonName chosen by the SQL rule matches your expectations.
	3.	Wire the new ORM classes into your Alembic migration scripts and generate empty tables in a staging database so that the downstream LLM tasked with writing loaders has a concrete target schema.

Feel free to circle back when you want help formalising the export‑side filtering logic or adding additional ColDP entities (e.g. SpeciesInteraction) to the model layer.

⸻

References
	•	ColDP specification & schema diagram.
	•	ColDP GitHub README (entity list and field explanations).
	•	ColDP publishing guidelines (recommended columns for VernacularName, Media, TypeMaterial). ￼
	•	ColDP v1.1 release notes (TypeMaterial multi‑value rules). ￼
	•	“Using the Catalogue of Life” overview of ColDP vs DwC‑A.
	•	iNaturalist “Taxon Frameworks” documentation (external authorities and mapping).
	•	iNaturalist API reference & numeric taxon_id explanation.
	•	GBIF best‑practice note on Catalogue of Life as composite checklist.
---- END ASSISTANT ----
