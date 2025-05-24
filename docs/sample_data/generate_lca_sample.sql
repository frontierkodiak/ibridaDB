-- SQL query for generating LCA sample data
-- Export ALL columns for the selected taxa (bees, wasps, key ancestors)

COPY (
    SELECT *
    FROM expanded_taxa t
    WHERE
        /* explicit IDs */
        t."taxonID" IN (
            630955,   -- Anthophila
            52747,    -- Vespidae
            47201,    -- Hymenoptera
            326777,   -- Aculeata           <-- new
            124417,   -- Apocrita           <-- new
            47216, 47337, 47338, 47369, 47218, 52775, 184884, 295935
        )
        /* or matching by scientific name (belt-and-braces in case IDs drift) */
        OR t."name" IN (
            'Animalia', 'Arthropoda', 'Insecta',
            'Hymenoptera', 'Aculeata',            -- added
            'Apocrita',                           -- added
            'Anthophila', 'Apidae', 'Apis', 'Apis mellifera',
            'Vespoidea', 'Vespidae', 'Vespinae', 'Vespa', 'Vespa mandarinia',
            'Vespa crabro', 'Vespula', 'Vespula vulgaris', 'Scoliidae'
        )
) TO '/tmp/expanded_taxa_lca_sample.tsv'
  WITH (FORMAT CSV, DELIMITER E'\t', HEADER TRUE);

-- Reminder for the fixture generator:
--   mv /tmp/expanded_taxa_lca_sample.tsv tests/sample_tsv/expanded_taxa.tsv