#!/bin/bash
# Check anthophila observation IDs against ibridaDB to identify duplicates.
# Uses direct SQL queries through Docker.

echo "=== Anthophila Duplicate Analysis ==="
echo ""

# First, extract unique observation IDs from our previous analysis
ANALYSIS_FILE="/home/caleb/repo/ibridaDB/anthophila_analysis.txt"

if [ ! -f "$ANALYSIS_FILE" ]; then
    echo "Error: Analysis file not found. Run anthophila_analysis.py first."
    exit 1
fi

# Extract observation IDs to temporary file (skip header)
TEMP_IDS="/tmp/anthophila_ids.txt"
tail -n +2 "$ANALYSIS_FILE" | cut -d',' -f1 | sort -u > "$TEMP_IDS"

TOTAL_IDS=$(wc -l < "$TEMP_IDS")
echo "Total unique anthophila observation IDs: $TOTAL_IDS"

# Create temporary table in database with our IDs
echo "Creating temporary table with anthophila IDs..."

docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -c "
    DROP TABLE IF EXISTS temp_anthophila_ids;
    CREATE TEMPORARY TABLE temp_anthophila_ids (observation_id INTEGER);
"

# Insert IDs into temporary table (in batches to avoid command line limits)
echo "Inserting IDs into database..."

split -l 1000 "$TEMP_IDS" /tmp/anthophila_batch_
for batch_file in /tmp/anthophila_batch_*; do
    if [ -s "$batch_file" ]; then
        IDS=$(tr '\n' ',' < "$batch_file" | sed 's/,$//')
        docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -c "
            INSERT INTO temp_anthophila_ids (observation_id) 
            VALUES ($(echo "$IDS" | sed 's/,/),(/g'));
        " 2>/dev/null
    fi
done

# Clean up batch files
rm -f /tmp/anthophila_batch_*

echo "Checking for duplicates in photos table..."

# Check duplicates against photos.photo_id
DUPLICATE_COUNT=$(docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -t -c "
    SELECT COUNT(DISTINCT t.observation_id)
    FROM temp_anthophila_ids t
    JOIN photos p ON t.observation_id = p.photo_id;
")

DUPLICATE_COUNT=$(echo $DUPLICATE_COUNT | tr -d ' ')

NEW_COUNT=$((TOTAL_IDS - DUPLICATE_COUNT))
DUPLICATE_PERCENT=$(echo "scale=1; $DUPLICATE_COUNT * 100 / $TOTAL_IDS" | bc)
NEW_PERCENT=$(echo "scale=1; $NEW_COUNT * 100 / $TOTAL_IDS" | bc)

echo ""
echo "=== RESULTS ==="
echo "Total unique anthophila observation IDs: $TOTAL_IDS"
echo "Found in database (duplicates): $DUPLICATE_COUNT"
echo "Duplicate percentage: $DUPLICATE_PERCENT%"
echo "New observations: $NEW_COUNT"
echo "New percentage: $NEW_PERCENT%"

# Get sample duplicates
echo ""
echo "Sample duplicate observation IDs:"
docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -t -c "
    SELECT t.observation_id
    FROM temp_anthophila_ids t
    JOIN photos p ON t.observation_id = p.photo_id
    LIMIT 5;
" | while read -r id; do
    id=$(echo $id | tr -d ' ')
    if [ ! -z "$id" ]; then
        echo "  $id -> https://www.inaturalist.org/observations/$id"
    fi
done

# Get sample new IDs
echo ""
echo "Sample NEW observation IDs (not in database):"
docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -t -c "
    SELECT t.observation_id
    FROM temp_anthophila_ids t
    LEFT JOIN photos p ON t.observation_id = p.photo_id
    WHERE p.photo_id IS NULL
    LIMIT 5;
" | while read -r id; do
    id=$(echo $id | tr -d ' ')
    if [ ! -z "$id" ]; then
        echo "  $id -> https://www.inaturalist.org/observations/$id"
    fi
done

# Save detailed results
RESULTS_FILE="/home/caleb/repo/ibridaDB/anthophila_duplicates_analysis.txt"

echo ""
echo "Saving detailed results to: $RESULTS_FILE"

cat > "$RESULTS_FILE" << EOF
Anthophila Duplicate Analysis Results
=====================================

Total unique anthophila observation IDs: $TOTAL_IDS
Found in database (duplicates): $DUPLICATE_COUNT
Duplicate percentage: $DUPLICATE_PERCENT%
New observations: $NEW_COUNT
New percentage: $NEW_PERCENT%

Duplicate observation IDs:
EOF

docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -t -c "
    SELECT t.observation_id
    FROM temp_anthophila_ids t
    JOIN photos p ON t.observation_id = p.photo_id
    ORDER BY t.observation_id;
" >> "$RESULTS_FILE"

echo "" >> "$RESULTS_FILE"
echo "New observation IDs:" >> "$RESULTS_FILE"

docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -t -c "
    SELECT t.observation_id
    FROM temp_anthophila_ids t
    LEFT JOIN photos p ON t.observation_id = p.photo_id
    WHERE p.photo_id IS NULL
    ORDER BY t.observation_id;
" >> "$RESULTS_FILE"

# Clean up
rm -f "$TEMP_IDS"

echo ""
echo "Analysis complete!"