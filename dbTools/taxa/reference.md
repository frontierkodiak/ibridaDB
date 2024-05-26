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