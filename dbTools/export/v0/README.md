Documentation for the new three-tier clade system:

Macroclade: High-level groupings anchored by a single root taxa node. Examples: arthropoda, aves.
Clade: Subsets within macroclades, still joined at a single root taxa node. Examples: insecta, arachnidae (within arthropoda).
Metaclade: Groupings of one or more clades, potentially crossing macroclade boundaries. Example: primary_terrestrial_arthropoda (includes insecta and arachnidae).

Preference hierarchy for table naming:

1. If a metaclade is specified, use the metaclade name.
2. If no metaclade but a clade is specified, use the clade name.
3. If neither metaclade nor clade is specified, use the macroclade name.

This system allows for flexible and precise control over taxa groupings while maintaining backward compatibility with the existing macroclade-level exports.