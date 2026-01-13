-- FINAL CHECK: Taxa with >25 observations in KEY CLADES that are affected
-- This gives us the ironclad answer

\timing on
\echo 'FINAL KEY CLADE CHECK FOR TAXA WITH >25 OBSERVATIONS'
\echo '===================================================='
\echo ''

-- Check the high-observation taxa we found earlier
\echo 'High-observation taxa (>25 obs) and their clades:'
\echo ''

WITH high_obs_taxa AS (
    SELECT taxon_id, name, rank, obs_count, ancestry
    FROM (VALUES
        (44062, 'Thomomys bottae', 'species', 7692, NULL),
        (37426, 'Trachylepis margaritifera', 'species', 1603, NULL),
        (48469, 'Yucca brevifolia brevifolia', 'variety', 1584, NULL),
        (42236, 'Vicugna vicugna', 'species', 1399, NULL),
        (41856, 'Lutrogale perspicillata', 'species', 1216, NULL),
        (47947, 'Ontholestes cingulatus', 'species', 1091, NULL),
        (47273, 'Elasmobranchii', 'class', 567, NULL),
        (33903, 'Pristurus rupestris', 'species', 374, NULL),
        (29691, 'Leptophis ahaetulla occidentalis', 'subspecies', 315, NULL),
        (34396, 'Homopholis walbergii', 'species', 277, NULL),
        (47952, 'Ontholestes tessellatus', 'species', 267, NULL),
        (41781, 'Aonyx capensis', 'species', 250, NULL),
        (47945, 'Ontholestes', 'genus', 144, NULL),
        (42235, 'Vicugna', 'genus', 142, NULL),
        (40485, 'Eptesicus furinalis', 'species', 124, NULL),
        (48727, 'Collinsia heterophylla heterophylla', 'subspecies', 116, NULL),
        (48106, 'Acer rubrum drummondii', 'subspecies', 101, NULL),
        (47948, 'Ontholestes haroldi', 'species', 66, NULL),
        (32344, 'Trachyboa boulengeri', 'species', 60, NULL),
        (29689, 'Leptophis ahaetulla praestans', 'subspecies', 55, NULL),
        (29690, 'Leptophis ahaetulla nigromarginatus', 'subspecies', 55, NULL),
        (44070, 'Thomomys bulbivorus', 'species', 50, NULL),
        (44068, 'Thomomys umbrinus', 'species', 40, NULL),
        (33905, 'Pristurus rupestris guweirensis', 'subspecies', 36, NULL),
        (43860, 'Allactaga elater', 'species', 35, NULL),
        (28561, 'Storeria hidalgoensis', 'species', 29, NULL)
    ) AS t(taxon_id, name, rank, obs_count, ancestry)
)
SELECT 
    h.taxon_id,
    h.name,
    h.rank,
    h.obs_count,
    t.ancestry,
    CASE 
        WHEN t.ancestry LIKE '%/47125/%' THEN 'ANGIOSPERMAE'
        WHEN t.ancestry LIKE '%/3/%' THEN 'AVES'
        WHEN t.ancestry LIKE '%/40151/%' THEN 'MAMMALIA'
        WHEN t.ancestry LIKE '%/20978/%' THEN 'AMPHIBIA'
        WHEN t.ancestry LIKE '%/26036/%' THEN 'REPTILIA'
        WHEN t.ancestry LIKE '%/47158/%' THEN 'INSECTA'
        WHEN t.ancestry LIKE '%/47119/%' THEN 'ARACHNIDA'
        ELSE 'OTHER/NONE'
    END as key_clade
FROM high_obs_taxa h
LEFT JOIN taxa t ON h.taxon_id = t.taxon_id
ORDER BY h.obs_count DESC;

\echo ''
\echo 'SUMMARY OF KEY CLADE IMPACTS (>25 obs only):'
\echo '============================================'
WITH high_obs_taxa AS (
    SELECT taxon_id, name, rank, obs_count
    FROM (VALUES
        (44062, 'Thomomys bottae', 'species', 7692),
        (37426, 'Trachylepis margaritifera', 'species', 1603),
        (48469, 'Yucca brevifolia brevifolia', 'variety', 1584),
        (42236, 'Vicugna vicugna', 'species', 1399),
        (41856, 'Lutrogale perspicillata', 'species', 1216),
        (47947, 'Ontholestes cingulatus', 'species', 1091),
        (47273, 'Elasmobranchii', 'class', 567),
        (33903, 'Pristurus rupestris', 'species', 374),
        (29691, 'Leptophis ahaetulla occidentalis', 'subspecies', 315),
        (34396, 'Homopholis walbergii', 'species', 277),
        (47952, 'Ontholestes tessellatus', 'species', 267),
        (41781, 'Aonyx capensis', 'species', 250),
        (47945, 'Ontholestes', 'genus', 144),
        (42235, 'Vicugna', 'genus', 142),
        (40485, 'Eptesicus furinalis', 'species', 124),
        (48727, 'Collinsia heterophylla heterophylla', 'subspecies', 116),
        (48106, 'Acer rubrum drummondii', 'subspecies', 101),
        (47948, 'Ontholestes haroldi', 'species', 66),
        (32344, 'Trachyboa boulengeri', 'species', 60),
        (29689, 'Leptophis ahaetulla praestans', 'subspecies', 55),
        (29690, 'Leptophis ahaetulla nigromarginatus', 'subspecies', 55),
        (44070, 'Thomomys bulbivorus', 'species', 50),
        (44068, 'Thomomys umbrinus', 'species', 40),
        (33905, 'Pristurus rupestris guweirensis', 'subspecies', 36),
        (43860, 'Allactaga elater', 'species', 35),
        (28561, 'Storeria hidalgoensis', 'species', 29)
    ) AS t(taxon_id, name, rank, obs_count)
),
clade_summary AS (
    SELECT 
        h.taxon_id,
        h.obs_count,
        t.ancestry,
        CASE 
            WHEN t.ancestry LIKE '%/47125/%' THEN 'ANGIOSPERMAE'
            WHEN t.ancestry LIKE '%/3/%' THEN 'AVES'
            WHEN t.ancestry LIKE '%/40151/%' THEN 'MAMMALIA'
            WHEN t.ancestry LIKE '%/20978/%' THEN 'AMPHIBIA'
            WHEN t.ancestry LIKE '%/26036/%' THEN 'REPTILIA'
            WHEN t.ancestry LIKE '%/47158/%' THEN 'INSECTA'
            WHEN t.ancestry LIKE '%/47119/%' THEN 'ARACHNIDA'
            ELSE 'OTHER/NONE'
        END as key_clade
    FROM high_obs_taxa h
    LEFT JOIN taxa t ON h.taxon_id = t.taxon_id
)
SELECT 
    key_clade,
    COUNT(*) as affected_taxa_count,
    SUM(obs_count) as total_observations,
    STRING_AGG(taxon_id::text, ', ' ORDER BY obs_count DESC) as taxon_ids
FROM clade_summary
GROUP BY key_clade
ORDER BY total_observations DESC;

\echo ''
\echo 'ANSWER: Taxa in KEY CLADES with >25 observations that are affected:'
\echo '====================================================================='
WITH high_obs_taxa AS (
    SELECT taxon_id, name, rank, obs_count
    FROM (VALUES
        (44062, 'Thomomys bottae', 'species', 7692),
        (37426, 'Trachylepis margaritifera', 'species', 1603),
        (48469, 'Yucca brevifolia brevifolia', 'variety', 1584),
        (42236, 'Vicugna vicugna', 'species', 1399),
        (41856, 'Lutrogale perspicillata', 'species', 1216),
        (47947, 'Ontholestes cingulatus', 'species', 1091),
        (47273, 'Elasmobranchii', 'class', 567),
        (33903, 'Pristurus rupestris', 'species', 374),
        (29691, 'Leptophis ahaetulla occidentalis', 'subspecies', 315),
        (34396, 'Homopholis walbergii', 'species', 277),
        (47952, 'Ontholestes tessellatus', 'species', 267),
        (41781, 'Aonyx capensis', 'species', 250),
        (47945, 'Ontholestes', 'genus', 144),
        (42235, 'Vicugna', 'genus', 142),
        (40485, 'Eptesicus furinalis', 'species', 124),
        (48727, 'Collinsia heterophylla heterophylla', 'subspecies', 116),
        (48106, 'Acer rubrum drummondii', 'subspecies', 101),
        (47948, 'Ontholestes haroldi', 'species', 66),
        (32344, 'Trachyboa boulengeri', 'species', 60),
        (29689, 'Leptophis ahaetulla praestans', 'subspecies', 55),
        (29690, 'Leptophis ahaetulla nigromarginatus', 'subspecies', 55),
        (44070, 'Thomomys bulbivorus', 'species', 50),
        (44068, 'Thomomys umbrinus', 'species', 40),
        (33905, 'Pristurus rupestris guweirensis', 'subspecies', 36),
        (43860, 'Allactaga elater', 'species', 35),
        (28561, 'Storeria hidalgoensis', 'species', 29)
    ) AS t(taxon_id, name, rank, obs_count)
)
SELECT 
    h.taxon_id,
    h.name,
    h.rank,
    h.obs_count,
    CASE 
        WHEN t.ancestry LIKE '%/47125/%' THEN 'ANGIOSPERMAE - YES'
        WHEN t.ancestry LIKE '%/3/%' THEN 'AVES - YES'
        WHEN t.ancestry LIKE '%/40151/%' THEN 'MAMMALIA - YES'
        WHEN t.ancestry LIKE '%/20978/%' THEN 'AMPHIBIA - YES'
        WHEN t.ancestry LIKE '%/26036/%' THEN 'REPTILIA - YES'
        WHEN t.ancestry LIKE '%/47158/%' THEN 'INSECTA - YES'
        WHEN t.ancestry LIKE '%/47119/%' THEN 'ARACHNIDA - YES'
        ELSE 'NOT IN KEY CLADES'
    END as in_key_clade
FROM high_obs_taxa h
LEFT JOIN taxa t ON h.taxon_id = t.taxon_id
WHERE t.ancestry LIKE '%/47125/%'
   OR t.ancestry LIKE '%/3/%'
   OR t.ancestry LIKE '%/40151/%'
   OR t.ancestry LIKE '%/20978/%'
   OR t.ancestry LIKE '%/26036/%'
   OR t.ancestry LIKE '%/47158/%'
   OR t.ancestry LIKE '%/47119/%'
ORDER BY h.obs_count DESC;