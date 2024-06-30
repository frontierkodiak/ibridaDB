--- Overview:
--- NA_<>_min50rg_taxa: Every species observed at least 50 times in region (RG).
------ Enforce RG for taxa list.
--- NA_<>_min50rg_taxa_obs: All observations where taxon_id is in `NA_<>_min50rg_taxa` table.
------ Accept all observations, not just research grade.
------ Filter out contested identifications: exclude species-level obs that are not RG.


-- Create table NAfull_min50all_taxa containing distinct taxon_id that meets certain criteria.
---- NOTATION:
------ <REGION_TAG>_min<MIN_OBS>_all_taxa
CREATE TABLE NAfull_min50all_taxa AS
SELECT  
    DISTINCT observations.taxon_id  
FROM  
    observations 
WHERE 
    observations.observation_uuid = ANY (
        SELECT observations.observation_uuid
        FROM observations
        JOIN taxa ON observations.taxon_id = taxa.taxon_id
        WHERE 
            NOT (taxa.rank_level = 10 AND observations.quality_grade != 'research')
            -- (xmin, ymin, xmax, ymax) = (-169.453125,12.211180,-23.554688,84.897147)
            AND observations.latitude BETWEEN 12.211180 AND 84.897147
            AND observations.longitude BETWEEN -169.453125 AND -23.554688
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

-- Create table NAfull_min50all_taxa_obs containing all observations where taxon_id is in NAfull_min50all_taxa table, including the 'origin' column.

---- NOTATION:
------ <REGION_TAG>_min<MIN_OBS>_all_taxa_obs
CREATE TABLE NAfull_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on, origin
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NAfull_min50all_taxa
    );
