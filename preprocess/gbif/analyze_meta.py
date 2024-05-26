import os
import csv
from collections import Counter
from tqdm import tqdm

# Base directory path
base_directory = "/pond/Polli/Datasets/anthophila/GBIF_occurences"

# Function to process the file and count unique values in a specified column
def count_unique_values(base_directory, source_file, column):
    file_path = os.path.join(base_directory, f"{source_file}.txt")
    value_counter = Counter()

    with open(file_path, 'r', newline='', encoding='utf-8') as file:
        reader = csv.DictReader(file, delimiter='\t')
        total_rows = sum(1 for _ in open(file_path, 'r', encoding='utf-8')) - 1  # Subtract 1 for header
        file.seek(0)  # Reset file pointer to the beginning
        next(reader)  # Skip header row

        for row in tqdm(reader, total=total_rows, desc="Processing rows"):
            value = row.get(column)
            if value:
                value_counter[value] += 1

    return value_counter

# Parameters
source_file = "multimedia"
column = "publisher"
operation = ["count_unique"]

# Process the file and count unique values in the specified column
unique_value_counts = count_unique_values(base_directory, source_file, column)

# Print the results
print(f"Unique value counts for column '{column}' in file '{source_file}.txt':")
for value, count in unique_value_counts.items():
    print(f"{value}: {count}")
