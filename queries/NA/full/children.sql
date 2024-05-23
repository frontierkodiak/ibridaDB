--- ARTHROPODA
CREATE TABLE NAfull_arthropoda_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/1/47120/%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_arthropoda_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_arthropoda_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_arthropoda_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_arthropoda_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_arthropoda_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_arthropoda_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_arthropoda_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_arthropoda_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_arthropoda_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_arthropoda_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_arthropoda_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_arthropoda_min50all_cap4000_photos;



--- AVES
CREATE TABLE NAfull_aves_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/1/2/355675/3/%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_aves_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_aves_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_aves_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_aves_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_aves_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_aves_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_aves_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_aves_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_aves_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_aves_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_aves_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_aves_min50all_cap4000_photos;
--- REPTILIA
CREATE TABLE NAfull_reptilia_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/1/2/355675/26036/%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_reptilia_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_reptilia_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_reptilia_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_reptilia_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_reptilia_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_reptilia_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_reptilia_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_reptilia_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_reptilia_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_reptilia_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_reptilia_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_reptilia_min50all_cap4000_photos;

--- MAMMALIA
CREATE TABLE NAfull_mammalia_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/1/2/355675/40151%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_mammalia_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_mammalia_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_mammalia_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_mammalia_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_mammalia_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_mammalia_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_mammalia_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_mammalia_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_mammalia_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_mammalia_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_mammalia_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_mammalia_min50all_cap4000_photos;


--- AMPHIBIA
CREATE TABLE NAfull_amphibia_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/1/2/355675/20978%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_amphibia_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_amphibia_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_amphibia_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_amphibia_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_amphibia_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_amphibia_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_amphibia_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_amphibia_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_amphibia_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_amphibia_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_amphibia_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_amphibia_min50all_cap4000_photos;


--- ANGIOSPERMAE
CREATE TABLE NAfull_angiospermae_min50all_cap4000 AS (
    SELECT  
        observation_uuid, 
        observer_id, 
        latitude, 
        longitude, 
        positional_accuracy, 
        taxon_id, 
        quality_grade,  
        observed_on,
        ROW_NUMBER() OVER (
            PARTITION BY taxon_id 
            ORDER BY RANDOM()
        ) as rn
    FROM
        NA_min50all_taxa_obs
    WHERE
        taxon_id IN (
            SELECT taxon_id
            FROM taxa
            WHERE ancestry LIKE '48460/47126/211194/47125/%'
        )
        AND taxon_id IN (
            SELECT taxon_id
            FROM NA_min50all_taxa_obs
            GROUP BY taxon_id
            HAVING COUNT(*) >= 50
        )
);
DELETE FROM NAfull_angiospermae_min50all_cap4000 WHERE rn > 4000;
CREATE TABLE NAfull_angiospermae_min50all_cap4000_photos AS
SELECT  
    t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
    t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
FROM
    NAfull_angiospermae_min50all_cap4000 t1
    JOIN photos t2
    ON t1.observation_uuid = t2.observation_uuid;
ALTER TABLE NAfull_angiospermae_min50all_cap4000_photos ADD COLUMN ancestry varchar(255);  
ALTER TABLE NAfull_angiospermae_min50all_cap4000_photos ADD COLUMN rank_level double precision;  
ALTER TABLE NAfull_angiospermae_min50all_cap4000_photos ADD COLUMN rank varchar(255);  
ALTER TABLE NAfull_angiospermae_min50all_cap4000_photos ADD COLUMN name varchar(255);  
UPDATE NAfull_angiospermae_min50all_cap4000_photos t1  
SET ancestry = t2.ancestry  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_angiospermae_min50all_cap4000_photos t1  
SET rank_level = t2.rank_level  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_angiospermae_min50all_cap4000_photos t1  
SET rank = t2.rank  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;  
UPDATE NAfull_angiospermae_min50all_cap4000_photos t1  
SET name = t2.name  
FROM taxa t2  
WHERE t1.taxon_id = t2.taxon_id;
VACUUM ANALYZE NAfull_angiospermae_min50all_cap4000_photos;

-- \copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_arthropoda_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_arthropoda_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_aves_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_aves_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_reptilia_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_reptilia_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_mammalia_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_mammalia_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_amphibia_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_amphibia_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM NAfull_angiospermae_min50all_cap4000_photos) TO '/exports/iNat-June2023/NAfull_angiospermae_min50all_cap4000_photos.csv' DELIMITER ',' CSV HEADER;
