#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="/datasets/taxa/catalogue_of_life/2024/ColDP"
OUTPUT_FILE="/home/caleb/repo/ibridaDB/dbTools/taxa/ColDP_raw_samples.txt"

# Start with an empty output file
> "$OUTPUT_FILE"

for filepath in "$INPUT_DIR"/*; do
  # Only process regular files that are not .png
  if [[ -f "$filepath" && "${filepath##*.}" != "png" ]]; then
    filename=$(basename "$filepath")
    {
      echo "<$filename>"
      echo "<head -n 10>"
      head -n 10 "$filepath"
      echo "</$filename>"
      echo "</head -n 10>"
      echo  # blank line between entries
    } >> "$OUTPUT_FILE"
  fi
done