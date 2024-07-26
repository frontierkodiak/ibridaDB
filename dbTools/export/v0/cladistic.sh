#!/bin/bash
## dbTools/export/v1/cladistic.sh

# This script implements a three-tier clade abstraction system:
# 1. Macroclade: High-level groupings (e.g., arthropoda, aves)
# 2. Clade: Subsets within macroclades (e.g., insecta, arachnidae within arthropoda)
# 3. Metaclade: Groupings of one or more clades (e.g., primary_terrestrial_arthropoda includes insecta and arachnidae)
#
# When exporting a metaclade:
# - The metaclade column is filled with the metaclade name
# - The macroclade column is filled with the parent macroclade
# - The clade column is filled with the specific clade for each observation
#
# When exporting a clade:
# - The clade column is filled with the clade name
# - The macroclade column is filled with the parent macroclade
# - The metaclade column is NULL
#
# When exporting a macroclade:
# - The macroclade column is filled with the macroclade name
# - The clade and metaclade columns are NULL. 
# FUTURE: macroclades should fill in clade cols for valid predefined clades.
# NOTE: clades are subsets of macroclades. macroclades are supersets of clades, but this relationship isn't explicitly defined.

# Use the variables passed from the wrapper script
DB_USER="${DB_USER}"
DB_NAME="${DB_NAME}"
REGION_TAG="${REGION_TAG}"
MIN_OBS="${MIN_OBS}"
MAX_RN="${MAX_RN}"
PRIMARY_ONLY="${PRIMARY_ONLY}"
EXPORT_SUBDIR="${EXPORT_SUBDIR}"
DB_CONTAINER="${DB_CONTAINER}"
HOST_EXPORT_BASE_PATH="${HOST_EXPORT_BASE_PATH}"
CONTAINER_EXPORT_BASE_PATH="${CONTAINER_EXPORT_BASE_PATH}"
ORIGIN_VALUE="${ORIGIN_VALUE}"
VERSION_VALUE="${VERSION_VALUE}"
EXPORT_GROUP="${EXPORT_GROUP}"
EXPORT_GROUP_TYPE="${EXPORT_GROUP_TYPE}"
PROCESS_OTHER=${PROCESS_OTHER:-false}  # Set to false by default, can be overridden by the wrapper script

# Debugging output
echo "DB_USER: ${DB_USER}"
echo "DB_NAME: ${DB_NAME}"
echo "REGION_TAG: ${REGION_TAG}"
echo "MIN_OBS: ${MIN_OBS}"
echo "MAX_RN: ${MAX_RN}"
echo "PRIMARY_ONLY: ${PRIMARY_ONLY}"
echo "EXPORT_SUBDIR: ${EXPORT_SUBDIR}"
echo "DB_CONTAINER: ${DB_CONTAINER}"
echo "HOST_EXPORT_BASE_PATH: ${HOST_EXPORT_BASE_PATH}"
echo "CONTAINER_EXPORT_BASE_PATH: ${CONTAINER_EXPORT_BASE_PATH}"
echo "ORIGIN_VALUE: ${ORIGIN_VALUE}"
echo "VERSION_VALUE: ${VERSION_VALUE}"
echo "EXPORT_GROUP: ${EXPORT_GROUP}"
echo "EXPORT_GROUP_TYPE: ${EXPORT_GROUP_TYPE}"
echo "Parent obs table: ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs"

# Define the three-tier taxonomy hierarchy
# Format: "group_type:ancestry_filter:parent_macroclade"
# For metaclades, the format is "group_type:clade1,clade2,..."
declare -A TAXA_HIERARCHY
TAXA_HIERARCHY=(
    ["arthropoda"]="macroclade:48460/1/47120/%:"
    ["insecta"]="clade:48460/1/47120/372739/47158/%:arthropoda"
    ["arachnidae"]="clade:48460/1/47120/245097/47119/%:arthropoda"
    ["primary_terrestrial_arthropoda"]="metaclade:insecta,arachnidae:"
    ["aves"]="macroclade:48460/1/2/355675/3/%:"
    ["reptilia"]="macroclade:48460/1/2/355675/26036/%:"
    ["mammalia"]="macroclade:48460/1/2/355675/40151%:"
    ["amphibia"]="macroclade:48460/1/2/355675/20978%:"
    ["angiospermae"]="macroclade:48460/47126/211194/47125/%:"
)

# Function to execute SQL commands
execute_sql() {
  local sql="$1"
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to print progress
print_progress() {
  local message="$1"
  echo "======================================"
  echo "$message"
  echo "======================================"
}

# Ensure export directory exists and is writable
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
CONTAINER_EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

if [ ! -d "$HOST_EXPORT_DIR" ]; then
  mkdir -p "$HOST_EXPORT_DIR"
fi

if [ ! -w "$HOST_EXPORT_DIR" ]; then
  echo "Error: Directory $HOST_EXPORT_DIR is not writable."
  exit 1
fi

# Function to create and populate the hierarchy table
create_hierarchy_table() {
    print_progress "Creating and populating hierarchy table"
    execute_sql "
    DROP TABLE IF EXISTS taxa_hierarchy;
    CREATE TABLE taxa_hierarchy (
        key TEXT,
        group_type TEXT,
        ancestry_filter TEXT,
        parent_macroclade TEXT
    );
    "
    
    for key in "${!TAXA_HIERARCHY[@]}"; do
        IFS=':' read -r temp_group_type temp_ancestry_filter temp_parent_macroclade <<< "${TAXA_HIERARCHY[$key]}"
        execute_sql "
        INSERT INTO taxa_hierarchy (key, group_type, ancestry_filter, parent_macroclade)
        VALUES ('$key', '$temp_group_type', '$temp_ancestry_filter', '$temp_parent_macroclade');
        "
    done
}

# Function to drop the hierarchy table
drop_hierarchy_table() {
    print_progress "Dropping hierarchy table"
    execute_sql "DROP TABLE IF EXISTS taxa_hierarchy;"
}

# Modified process_taxa_group function
process_taxa_group() {
    local group=$1
    local group_type
    local ancestry_filter
    local parent_macroclade
    
    if [ "$group" = "other" ]; then
        group_type="other"
        ancestry_filter=""
        parent_macroclade=""
    else
        IFS=':' read -r group_type ancestry_filter parent_macroclade <<< "${TAXA_HIERARCHY[$group]}"
    fi
    
    local table_name="${group}"
    local photos_table_name="${table_name}_photos"
    local export_path="${CONTAINER_EXPORT_DIR}/${photos_table_name}.csv"

    # Construct the WHERE clause for ancestry filtering
    local ancestry_where_clause
    if [ "$group" = "other" ]; then
        ancestry_where_clause="ancestry NOT LIKE ANY (SELECT ancestry_filter FROM taxa_hierarchy WHERE group_type = 'macroclade')"
    elif [ "$group_type" = "metaclade" ]; then
        ancestry_where_clause="ancestry LIKE ANY (SELECT ancestry_filter FROM taxa_hierarchy WHERE key = ANY(string_to_array('$ancestry_filter', ',')))"
    else
        ancestry_where_clause="ancestry LIKE '${ancestry_filter}'"
    fi

    # Create main table
    print_progress "Creating table ${table_name}"
    execute_sql "
    DROP TABLE IF EXISTS ${table_name};
    CREATE TABLE ${table_name} AS (
        SELECT  
            observation_uuid, 
            observer_id, 
            latitude, 
            longitude, 
            positional_accuracy, 
            taxon_id, 
            quality_grade,  
            observed_on,
            CASE 
                WHEN '${group_type}' = 'macroclade' THEN '${group}'
                WHEN '${group_type}' = 'clade' THEN '${parent_macroclade}'
                WHEN '${group_type}' = 'metaclade' THEN 
                    (SELECT DISTINCT parent_macroclade FROM taxa_hierarchy WHERE key = ANY(string_to_array('${ancestry_filter}', ',')))
                ELSE NULL
            END AS macroclade,
            CASE 
                WHEN '${group_type}' = 'clade' THEN '${group}'
                WHEN '${group_type}' = 'metaclade' THEN 
                    (SELECT key FROM taxa_hierarchy 
                     WHERE ancestry_filter = (
                         SELECT ancestry_filter FROM taxa_hierarchy 
                         WHERE key = ANY(string_to_array('${ancestry_filter}', ','))
                         AND ancestry LIKE ancestry_filter
                         LIMIT 1
                     )
                    )
                ELSE NULL
            END AS clade,
            CASE 
                WHEN '${group_type}' = 'metaclade' THEN '${group}'
                ELSE NULL
            END AS metaclade,
            ROW_NUMBER() OVER (
                PARTITION BY taxon_id 
                ORDER BY RANDOM()
            ) as rn
        FROM
            ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs
        WHERE
            taxon_id IN (
                SELECT taxon_id
                FROM taxa
                WHERE ${ancestry_where_clause}
            )
            AND taxon_id IN (
                SELECT taxon_id
                FROM ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs
                GROUP BY taxon_id
                HAVING COUNT(*) >= ${MIN_OBS}
            )
    );
    DELETE FROM ${table_name} WHERE rn > ${MAX_RN};
    "

    # Create photos table
    print_progress "Creating table ${photos_table_name}"
    execute_sql "
    DROP TABLE IF EXISTS ${photos_table_name};
    CREATE TABLE ${photos_table_name} AS
    SELECT  
        t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
        t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position,
        t1.macroclade, t1.clade, t1.metaclade
    FROM
        ${table_name} t1
        JOIN photos t2
        ON t1.observation_uuid = t2.observation_uuid
    WHERE 1=1 ${photos_where_clause};

    ALTER TABLE ${photos_table_name} ADD COLUMN ancestry varchar(255);  
    ALTER TABLE ${photos_table_name} ADD COLUMN rank_level double precision;  
    ALTER TABLE ${photos_table_name} ADD COLUMN rank varchar(255);  
    ALTER TABLE ${photos_table_name} ADD COLUMN name varchar(255);  

    UPDATE ${photos_table_name} t1  
    SET ancestry = t2.ancestry,
        rank_level = t2.rank_level,
        rank = t2.rank,
        name = t2.name
    FROM taxa t2  
    WHERE t1.taxon_id = t2.taxon_id;
    "

    # Export photos table to CSV
    print_progress "Exporting table ${photos_table_name} to CSV"
    execute_sql "\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name, macroclade, clade, metaclade FROM ${photos_table_name}) TO '${export_path}' DELIMITER ',' CSV HEADER;"

    execute_sql "VACUUM ANALYZE ${photos_table_name};"
}

# Main execution flow in cladistic.sh
create_hierarchy_table
process_taxa_group "$EXPORT_GROUP"
if [ "$PROCESS_OTHER" = true ]; then
    process_taxa_group "other"
fi
drop_hierarchy_table

# Create the export summary file
summary_file="${HOST_EXPORT_DIR}/export_summary.txt"

{
    echo "Export Summary"
    echo "=============="
    echo "DB_USER: ${DB_USER}"
    echo "DB_NAME: ${DB_NAME}"
    echo "REGION_TAG: ${REGION_TAG}"
    echo "MIN_OBS: ${MIN_OBS}"
    echo "MAX_RN: ${MAX_RN}"
    echo "PRIMARY_ONLY: ${PRIMARY_ONLY}"
    echo "EXPORT_SUBDIR: ${EXPORT_SUBDIR}"
    echo "DB_CONTAINER: ${DB_CONTAINER}"
    echo "HOST_EXPORT_BASE_PATH: ${HOST_EXPORT_BASE_PATH}"
    echo "CONTAINER_EXPORT_BASE_PATH: ${CONTAINER_EXPORT_BASE_PATH}"
    echo "ORIGIN_VALUE: ${ORIGIN_VALUE}"
    echo "VERSION_VALUE: ${VERSION_VALUE}"
    echo "EXPORT_GROUP: ${EXPORT_GROUP}"
    echo "EXPORT_GROUP_TYPE: ${EXPORT_GROUP_TYPE}"
    echo "PROCESS_OTHER: ${PROCESS_OTHER}"
    echo ""
    echo "Table Row Counts:"
    table_name="${EXPORT_GROUP}"
    row_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ${table_name};" | tr -d '[:space:]')
    echo "${table_name}: ${row_count} rows"
    
    if [ "$PROCESS_OTHER" = true ]; then
        table_name="other"
        row_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ${table_name};" | tr -d '[:space:]')
        echo "${table_name}: ${row_count} rows"
    fi
    
    echo ""
    echo "Column Names:"
    table_name="${EXPORT_GROUP}_photos"
    columns=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '${table_name}';" | tr -d '[:space:]' | paste -sd, -)
    echo "${table_name}: ${columns}"
    
    if [ "$PROCESS_OTHER" = true ]; then
        table_name="other_photos"
        columns=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '${table_name}';" | tr -d '[:space:]' | paste -sd, -)
        echo "${table_name}: ${columns}"
    fi
} > "$summary_file"

print_progress "Export summary written to ${summary_file}"

print_progress "Taxa group processed and exported"