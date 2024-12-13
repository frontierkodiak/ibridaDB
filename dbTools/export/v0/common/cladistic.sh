#!/bin/bash

# Note: functions.sh is already sourced from main.sh

# Function to get taxa IDs for a given metaclade
get_metaclade_taxa() {
    local metaclade=$1
    case $metaclade in
        "primary_terrestrial_arthropoda")
            # Include Insecta and Arachnida, exclude aquatic groups
            execute_sql "
                WITH RECURSIVE taxonomy AS (
                    SELECT taxon_id, ancestry, rank, name, active
                    FROM taxa
                    WHERE name IN ('Insecta', 'Arachnida')
                    UNION ALL
                    SELECT t.taxon_id, t.ancestry, t.rank, t.name, t.active
                    FROM taxa t
                    INNER JOIN taxonomy tax ON t.ancestry LIKE tax.ancestry || '/%'
                        OR t.ancestry = tax.ancestry
                    WHERE t.active = true
                )
                SELECT DISTINCT taxon_id 
                FROM taxonomy
                WHERE active = true
                AND taxon_id NOT IN (
                    SELECT DISTINCT t.taxon_id
                    FROM taxa t
                    WHERE t.name IN ('Ephemeroptera', 'Plecoptera', 'Trichoptera', 'Odonata')
                    OR t.ancestry LIKE '%/48549%'  -- Exclude aquatic insects
                );"
            ;;
        "amphibia")
            execute_sql "
                WITH RECURSIVE taxonomy AS (
                    SELECT taxon_id, ancestry, rank, name, active
                    FROM taxa
                    WHERE name = 'Amphibia'
                    UNION ALL
                    SELECT t.taxon_id, t.ancestry, t.rank, t.name, t.active
                    FROM taxa t
                    INNER JOIN taxonomy tax ON t.ancestry LIKE tax.ancestry || '/%'
                        OR t.ancestry = tax.ancestry
                    WHERE t.active = true
                )
                SELECT DISTINCT taxon_id 
                FROM taxonomy
                WHERE active = true;"
            ;;
        *)
            echo "Unknown metaclade: $metaclade"
            exit 1
            ;;
    esac
}

# Create filtered tables based on metaclade
print_progress "Creating filtered tables for ${EXPORT_GROUP}"
execute_sql "
CREATE TEMPORARY TABLE metaclade_taxa AS
$(get_metaclade_taxa ${EXPORT_GROUP});

CREATE TABLE ${EXPORT_GROUP}_observations AS
SELECT ${OBS_COLUMNS}
FROM ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs obs
WHERE obs.taxon_id IN (SELECT taxon_id FROM metaclade_taxa);"

# Export filtered observations
print_progress "Exporting filtered observations"
if [ "$PRIMARY_ONLY" = true ]; then
    execute_sql "\COPY (
        SELECT o.*, 
               p.photo_uuid,
               p.photo_id,
               p.extension,
               p.license,
               p.width,
               p.height,
               p.position
        FROM ${EXPORT_GROUP}_observations o
        JOIN photos p ON o.observation_uuid = p.observation_uuid
        WHERE p.position = 0
        AND o.quality_grade = 'research'
        ORDER BY random()
        LIMIT ${MAX_RN}
    ) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv' WITH CSV HEADER DELIMITER E'\t';"
else
    execute_sql "\COPY (
        SELECT o.*, 
               p.photo_uuid,
               p.photo_id,
               p.extension,
               p.license,
               p.width,
               p.height,
               p.position
        FROM ${EXPORT_GROUP}_observations o
        JOIN photos p ON o.observation_uuid = p.observation_uuid
        WHERE o.quality_grade = 'research'
        ORDER BY random()
        LIMIT ${MAX_RN}
    ) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv' WITH CSV HEADER DELIMITER E'\t';"
fi

# Create summary of exported data
print_progress "Creating export statistics"
STATS=$(execute_sql "
WITH export_stats AS (
    SELECT 
        COUNT(DISTINCT observation_uuid) as num_observations,
        COUNT(DISTINCT taxon_id) as num_taxa,
        COUNT(DISTINCT observer_id) as num_observers
    FROM ${EXPORT_GROUP}_observations
)
SELECT format(
    'Exported Data Statistics:
    Observations: %s
    Unique Taxa: %s
    Unique Observers: %s',
    num_observations, num_taxa, num_observers
)
FROM export_stats;")

echo "${STATS}" >> "${HOST_EXPORT_DIR}/export_summary.txt"

print_progress "Cladistic filtering complete"