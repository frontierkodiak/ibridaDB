'''
Analyze file extensions, recode all to .jpg if not already. 

Refactor position in filename to be 0-indexed.
'''

import os
from collections import Counter
from tqdm import tqdm

# Path to the parent directory
parent_directory = "/pond/Polli/Datasets/anthophila"

# Dictionary to count file extensions
file_extensions = Counter()

# List to store paths of txt and xml files
txt_files = []
xml_files = []

# Count total files for progress bar
total_files = sum([len(files) for r, d, files in os.walk(parent_directory)])

# Walk through the directory structure with tqdm progress bar
for root, dirs, files in tqdm(os.walk(parent_directory), total=total_files):
    for file in files:
        # Split the file name to get the extension
        _, extension = os.path.splitext(file)
        # Add the extension to the counter
        file_extensions[extension.lower()] += 1
        
        # Store paths of txt and xml files
        if extension.lower() == '.txt':
            txt_files.append(os.path.join(root, file))
        elif extension.lower() == '.xml':
            xml_files.append(os.path.join(root, file))

# Print the count of each file extension
print("File extensions and their counts:")
for extension, count in file_extensions.items():
    print(f"{extension}: {count}")

# Print the paths of txt files
print("\nPaths of .txt files:")
for path in txt_files:
    print(path)

# Print the paths of xml files
print("\nPaths of .xml files:")
for path in xml_files:
    print(path)
