--- Overview:
--- NA_<>_min50rg_taxa: Every species observed at least 50 times in region (RG).
------ Enforce RG for taxa list.
--- NA_<>_min50rg_taxa_obs: All observations where taxon_id is in `NA_<>_min50rg_taxa` table.
------ Accept all observations, not just research grade.
------ Filter out contested identifications: exclude species-level obs that are not RG.


--------- EUR_west_min50all_taxa  ----------------------------
CREATE TABLE EUR_west_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-12.128906,40.245992,12.480469,60.586967
            AND observations.latitude BETWEEN 40.245992 AND 60.586967
            AND observations.longitude BETWEEN -12.128906 AND 12.480469
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table EUR_west_min50all_taxa_obs containing all observations where taxon_id is in EUR_west_min50all_taxa table.
CREATE TABLE EUR_west_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM EUR_west_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- EUR_north_min50all_taxa  ----------------------------
CREATE TABLE EUR_north_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-25.927734,54.673831,45.966797,71.357067
            AND observations.latitude BETWEEN 54.673831 AND 71.357067
            AND observations.longitude BETWEEN -25.927734 AND 45.966797
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table EUR_north_min50all_taxa_obs containing all observations where taxon_id is in EUR_north_min50all_taxa table.
CREATE TABLE EUR_north_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM EUR_north_min50all_taxa
    )
    ;
--------------------------------------------------------



--------- EUR_east_min50all_taxa  ----------------------------
CREATE TABLE EUR_east_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (10.722656,41.771312,39.550781,59.977005)
            AND observations.latitude BETWEEN 41.771312 AND 59.977005
            AND observations.longitude BETWEEN 10.722656 AND 39.550781
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table EUR_east_min50all_taxa_obs containing all observations where taxon_id is in EUR_east_min50all_taxa table.
CREATE TABLE EUR_east_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM EUR_east_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- MED_min50all_taxa  ----------------------------
CREATE TABLE MED_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (-16.259766,29.916852,36.474609,46.316584)
            AND observations.latitude BETWEEN 29.916852 AND 46.316584
            AND observations.longitude BETWEEN -16.259766 AND 36.474609
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table MED_min50all_taxa_obs containing all observations where taxon_id is in MED_min50all_taxa table.
CREATE TABLE MED_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM MED_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- AUS_min50all_taxa  ----------------------------
CREATE TABLE AUS_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (111.269531,-47.989922,181.230469,-9.622414)
            AND observations.latitude BETWEEN -47.989922 AND -9.622414
            AND observations.longitude BETWEEN 111.269531 AND 181.230469
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table AUS_min50all_taxa_obs containing all observations where taxon_id is in AUS_min50all_taxa table.
CREATE TABLE AUS_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM AUS_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- ASIA_southeast_min50all_taxa  ----------------------------
CREATE TABLE ASIA_southeast_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (82.441406,-11.523088,153.457031,28.613459)
            AND observations.latitude BETWEEN -11.523088 AND 28.613459
            AND observations.longitude BETWEEN 82.441406 AND 153.457031
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_southeast_min50all_taxa_obs containing all observations where taxon_id is in ASIA_southeast_min50all_taxa table.
CREATE TABLE ASIA_southeast_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_southeast_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- ASIA_east_min50all_taxa  ----------------------------
CREATE TABLE ASIA_east_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (462.304688,23.241346,550.195313,78.630006
            AND observations.latitude BETWEEN 23.241346 AND 78.630006
            AND observations.longitude BETWEEN 462.304688 AND 550.195313
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_east_min50all_taxa_obs containing all observations where taxon_id is in ASIA_east_min50all_taxa table.
CREATE TABLE ASIA_east_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_east_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- ASIA_central_min50all_taxa  ----------------------------
CREATE TABLE ASIA_central_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = 408.515625,36.031332,467.753906,76.142958)
            AND observations.latitude BETWEEN 36.031332 AND 76.142958
            AND observations.longitude BETWEEN 408.515625 AND 467.753906
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_central_min50all_taxa_obs containing all observations where taxon_id is in ASIA_central_min50all_taxa table.
CREATE TABLE ASIA_central_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_central_min50all_taxa
    )
    ;
--------------------------------------------------------

--------- ASIA_south_min50all_taxa  ----------------------------
CREATE TABLE ASIA_south_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = 420.468750,1.581830,455.097656,39.232253
            AND observations.latitude BETWEEN 1.581830 AND 39.232253
            AND observations.longitude BETWEEN 420.468750 AND 455.097656
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_south_min50all_taxa_obs containing all observations where taxon_id is in ASIA_south_min50all_taxa table.
CREATE TABLE ASIA_south_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_south_min50all_taxa
    )
    ;
--------------------------------------------------------

--------- ASIA_southwest_min50all_taxa  ----------------------------
CREATE TABLE ASIA_southwest_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = 386.718750,12.897489,423.281250,48.922499
            AND observations.latitude BETWEEN 12.897489 AND 48.922499
            AND observations.longitude BETWEEN 386.718750 AND 423.281250
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_southwest_min50all_taxa_obs containing all observations where taxon_id is in ASIA_southwest_min50all_taxa table.
CREATE TABLE ASIA_southwest_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_southwest_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- ASIA_northwest_min50all_taxa  ----------------------------
CREATE TABLE ASIA_northwest_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = 393.046875,46.800059,473.203125,81.621352
            AND observations.latitude BETWEEN 46.800059 AND 81.621352
            AND observations.longitude BETWEEN 393.046875 AND 473.203125
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table ASIA_northwest_min50all_taxa_obs containing all observations where taxon_id is in ASIA_northwest_min50all_taxa table.
CREATE TABLE ASIA_northwest_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ASIA_northwest_min50all_taxa
    )
    ;
--------------------------------------------------------

--------- SA_min50all_taxa  ----------------------------
CREATE TABLE SA_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = (271.230469,-57.040730,330.644531,15.114553)
            AND observations.latitude BETWEEN -57.040730 AND 15.114553
            AND observations.longitude BETWEEN 271.230469 AND 330.644531
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table SA_min50all_taxa_obs containing all observations where taxon_id is in SA_min50all_taxa table.
CREATE TABLE SA_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM SA_min50all_taxa
    )
    ;
--------------------------------------------------------


--------- AFR_min50all_taxa  ----------------------------
CREATE TABLE AFR_min50all_taxa AS
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
            -- (xmin, ymin, xmax, ymax) = 339.082031,-37.718590,421.699219,39.232253
            AND observations.latitude BETWEEN -37.718590 AND 39.232253
            AND observations.longitude BETWEEN 339.082031 AND 421.699219
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= 50
    );

--- Create table AFR_min50all_taxa_obs containing all observations where taxon_id is in AFR_min50all_taxa table.
CREATE TABLE AFR_min50all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM AFR_min50all_taxa
    )
    ;
--------------------------------------------------------