--- Overview:
--- NA_<>_min50rg_taxa: Every species observed at least 50 times in region (RG).
------ Enforce RG for taxa list.
--- NA_<>_min50rg_taxa_obs: All observations where taxon_id is in `NA_<>_min50rg_taxa` table.
------ Accept all observations, not just research grade.
------ Filter out contested identifications: exclude species-level obs that are not RG.

--------- NA_east_min50all_taxa ----------------
CREATE TABLE NA_east_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-91.0,24.521208,-51.0,52.0)
            AND observations.latitude BETWEEN 24.521208 AND 52.0
            AND observations.longitude BETWEEN -91.0 AND -51.0
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table NA_east_min50all_taxa_obs containing all observations where taxon_id is in NA_east_min50all_taxa table.
CREATE TABLE NA_east_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NA_east_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- NA_central_min50all_taxa ----------------
CREATE TABLE NA_central_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-114.16,33.57,-90.26,58.26)
            AND observations.latitude BETWEEN 33.57 AND 58.26
            AND observations.longitude BETWEEN -114.16 AND -90.26
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table NA_central_min50all_taxa_obs containing all observations where taxon_id is in NA_central_min50all_taxa table.
CREATE TABLE NA_central_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NA_central_min50all_taxa
    )
    ;
--------------------------------------------------------

--------- NA_west_min50all_taxa ----------------
CREATE TABLE NA_west_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-136.49,32.47,-112.94,58.95)
            AND observations.latitude BETWEEN 32.47 AND 58.95
            AND observations.longitude BETWEEN -136.49 AND -112.94
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table NA_west_min50all_taxa_obs containing all observations where taxon_id is in NA_west_min50all_taxa table.
CREATE TABLE NA_west_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NA_west_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- NA_north_min50all_taxa ----------------
CREATE TABLE NA_north_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-169.8,47.64,-52.03,83.44)
            AND observations.latitude BETWEEN 47.64 AND 83.44
            AND observations.longitude BETWEEN -169.8 AND -52.03
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table NA_north_min50all_taxa_obs containing all observations where taxon_id is in NA_north_min50all_taxa table.
CREATE TABLE NA_north_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NA_north_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- NA_south_min50all_taxa  ----------------------------
CREATE TABLE NA_south_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-118.13,19.56,-93.16,36.74)
            AND observations.latitude BETWEEN 19.56 AND 36.74
            AND observations.longitude BETWEEN -118.13 AND -93.16
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table NA_south_min50all_taxa_obs containing all observations where taxon_id is in NA_south_min50all_taxa table.
CREATE TABLE NA_south_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM NA_south_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- CA_min50all_taxa  ----------------------------
CREATE TABLE CA_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-108.02,5.01,-74.27,23.16)
            AND observations.latitude BETWEEN 5.01 AND 23.16
            AND observations.longitude BETWEEN -108.02 AND -74.27
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table CA_min50all_taxa_obs containing all observations where taxon_id is in CA_min50all_taxa table.
CREATE TABLE CA_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM CA_min50all_taxa
    )
    ;
--------------------------------------------------------