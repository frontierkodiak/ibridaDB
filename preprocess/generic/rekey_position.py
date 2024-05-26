import os
import re

# Base directory containing the image subdirectories
base_directory = "/pond/Polli/Datasets/anthophila/imgs"

# Regular expression to match the filename pattern and capture parts of it
filename_pattern = re.compile(r'^(.*?_\d+)_(\d+)(\.\w+)$')

def rekey_position_in_filenames(base_directory):
    # Iterate over all subdirectories
    for subdir, _, files in os.walk(base_directory):
        # Collect files with their current position values
        file_info = []
        
        for file in files:
            match = filename_pattern.match(file)
            if match:
                base_name = match.group(1)
                position = int(match.group(2))
                extension = match.group(3)
                file_info.append((file, base_name, position, extension))
        
        # Sort files by their current position values
        file_info.sort(key=lambda x: x[2])
        
        # Rename files by subtracting 1 from the position value
        for file, base_name, position, extension in file_info:
            new_position = position - 1
            new_filename = f"{base_name}_{new_position}{extension}"
            old_filepath = os.path.join(subdir, file)
            new_filepath = os.path.join(subdir, new_filename)
            os.rename(old_filepath, new_filepath)
            print(f"Renamed: {old_filepath} -> {new_filepath}")

# Run the function to rekey position in filenames
rekey_position_in_filenames(base_directory)
