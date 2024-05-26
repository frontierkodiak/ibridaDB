'''
# code_to_name: maps taxon rank polli-style code to rank names  
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
'''

import os
import argparse

def get_rank_code(name):
    parts = name.split('_')
    if len(parts) == 1:
        return 'L20'  # Genus
    elif len(parts) == 2:
        return 'L10'  # Species
    elif len(parts) == 3:
        return 'L5'   # Subspecies
    else:
        return 'Unknown'

# Parse command line arguments
parser = argparse.ArgumentParser()
parser.add_argument('--rename', action='store_true', help='Prepend rank code to directory name')
args = parser.parse_args()

# Directory containing the taxa subdirectories
base_dir = "/pond/Polli/Datasets/anthophila/imgs"

# Output file path
output_file = "/pond/Polli/Datasets/anthophila/dir_rank_code_mapping.txt"

# Get the list of subdirectories
subdirs = [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]

# Generate the mapping dictionary
mapping_dict = {subdir: get_rank_code(subdir) for subdir in subdirs}

# HACK:
args.rename = True

# Save the mapping dictionary to a file
with open(output_file, 'w') as f:
    for subdir, rank_code in mapping_dict.items():
        f.write(f"{subdir}:{rank_code}\n")
        
        if args.rename:
            old_path = os.path.join(base_dir, subdir)
            new_path = os.path.join(base_dir, f"{rank_code}_{subdir}")
            os.rename(old_path, new_path)

print(f"Mapping saved to {output_file}")

if args.rename:
    print("Directory names updated with rank codes.")