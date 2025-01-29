# expanded_taxa

One row per taxon. Expands the 'ancestry' column from the 'taxa' table into a set of columns.
    Can be much more performany than recursive string parsing for ancestry.

```sql
ibrida-v0-r1=# \d expanded_taxa
                        Table "public.expanded_taxa"
      Column      |          Type          | Collation | Nullable | Default
------------------+------------------------+-----------+----------+---------
 taxonID          | integer                |           | not null |
 rankLevel        | double precision       |           |          |
 rank             | character varying(255) |           |          |
 name             | character varying(255) |           |          |
 taxonActive      | boolean                |           |          |
 L5_taxonID       | integer                |           |          |
 L5_name          | character varying(255) |           |          |
 L5_commonName    | character varying(255) |           |          |
 L10_taxonID      | integer                |           |          |
 L10_name         | character varying(255) |           |          |
 L10_commonName   | character varying(255) |           |          |
 L11_taxonID      | integer                |           |          |
 L11_name         | character varying(255) |           |          |
 L11_commonName   | character varying(255) |           |          |
 L12_taxonID      | integer                |           |          |
 L12_name         | character varying(255) |           |          |
 L12_commonName   | character varying(255) |           |          |
 L13_taxonID      | integer                |           |          |
 L13_name         | character varying(255) |           |          |
 L13_commonName   | character varying(255) |           |          |
 L15_taxonID      | integer                |           |          |
 L15_name         | character varying(255) |           |          |
 L15_commonName   | character varying(255) |           |          |
 L20_taxonID      | integer                |           |          |
 L20_name         | character varying(255) |           |          |
 L20_commonName   | character varying(255) |           |          |
 L24_taxonID      | integer                |           |          |
 L24_name         | character varying(255) |           |          |
 L24_commonName   | character varying(255) |           |          |
 L25_taxonID      | integer                |           |          |
 L25_name         | character varying(255) |           |          |
 L25_commonName   | character varying(255) |           |          |
 L26_taxonID      | integer                |           |          |
 L26_name         | character varying(255) |           |          |
 L26_commonName   | character varying(255) |           |          |
 L27_taxonID      | integer                |           |          |
 L27_name         | character varying(255) |           |          |
 L27_commonName   | character varying(255) |           |          |
 L30_taxonID      | integer                |           |          |
 L30_name         | character varying(255) |           |          |
 L30_commonName   | character varying(255) |           |          |
 L32_taxonID      | integer                |           |          |
 L32_name         | character varying(255) |           |          |
 L32_commonName   | character varying(255) |           |          |
 L33_taxonID      | integer                |           |          |
 L33_name         | character varying(255) |           |          |
 L33_commonName   | character varying(255) |           |          |
 L33_5_taxonID    | integer                |           |          |
 L33_5_name       | character varying(255) |           |          |
 L33_5_commonName | character varying(255) |           |          |
 L34_taxonID      | integer                |           |          |
 L34_name         | character varying(255) |           |          |
 L34_commonName   | character varying(255) |           |          |
 L34_5_taxonID    | integer                |           |          |
 L34_5_name       | character varying(255) |           |          |
 L34_5_commonName | character varying(255) |           |          |
 L35_taxonID      | integer                |           |          |
 L35_name         | character varying(255) |           |          |
 L35_commonName   | character varying(255) |           |          |
 L37_taxonID      | integer                |           |          |
 L37_name         | character varying(255) |           |          |
 L37_commonName   | character varying(255) |           |          |
 L40_taxonID      | integer                |           |          |
 L40_name         | character varying(255) |           |          |
 L40_commonName   | character varying(255) |           |          |
 L43_taxonID      | integer                |           |          |
 L43_name         | character varying(255) |           |          |
 L43_commonName   | character varying(255) |           |          |
 L44_taxonID      | integer                |           |          |
 L44_name         | character varying(255) |           |          |
 L44_commonName   | character varying(255) |           |          |
 L45_taxonID      | integer                |           |          |
 L45_name         | character varying(255) |           |          |
 L45_commonName   | character varying(255) |           |          |
 L47_taxonID      | integer                |           |          |

...skipping 1 line
 L47_commonName   | character varying(255) |           |          |
 L50_taxonID      | integer                |           |          |
 L50_name         | character varying(255) |           |          |
 L50_commonName   | character varying(255) |           |          |
 L53_taxonID      | integer                |           |          |
 L53_name         | character varying(255) |           |          |
 L53_commonName   | character varying(255) |           |          |
 L57_taxonID      | integer                |           |          |
 L57_name         | character varying(255) |           |          |
 L57_commonName   | character varying(255) |           |          |
 L60_taxonID      | integer                |           |          |
 L60_name         | character varying(255) |           |          |
 L60_commonName   | character varying(255) |           |          |
 L67_taxonID      | integer                |           |          |
 L67_name         | character varying(255) |           |          |
 L67_commonName   | character varying(255) |           |          |
 L70_taxonID      | integer                |           |          |
 L70_name         | character varying(255) |           |          |
 L70_commonName   | character varying(255) |           |          |
Indexes:
    "expanded_taxa_pkey" PRIMARY KEY, btree ("taxonID")
    "idx_expanded_taxa_l10_taxonid" btree ("L10_taxonID")
    "idx_expanded_taxa_l20_taxonid" btree ("L20_taxonID")
    "idx_expanded_taxa_l30_taxonid" btree ("L30_taxonID")
    "idx_expanded_taxa_l40_taxonid" btree ("L40_taxonID")
    "idx_expanded_taxa_l50_taxonid" btree ("L50_taxonID")
    "idx_expanded_taxa_l60_taxonid" btree ("L60_taxonID")
    "idx_expanded_taxa_l70_taxonid" btree ("L70_taxonID")
    "idx_expanded_taxa_name" btree (name)
    "idx_expanded_taxa_ranklevel" btree ("rankLevel")
    "idx_expanded_taxa_taxonid" btree ("taxonID")
```
---

# taxa

One row per taxon.

```sql
ibrida-v0-r1=# \d taxa
                         Table "public.taxa"
   Column   |          Type          | Collation | Nullable | Default
------------+------------------------+-----------+----------+---------
 taxon_id   | integer                |           | not null |
 ancestry   | character varying(255) |           |          |
 rank_level | double precision       |           |          |
 rank       | character varying(255) |           |          |
 name       | character varying(255) |           |          |
 active     | boolean                |           |          |
 origin     | character varying(255) |           |          |
 version    | character varying(255) |           |          |
 release    | character varying(255) |           |          |
Indexes:
    "index_taxa_active" btree (active)
    "index_taxa_name" gin (to_tsvector('simple'::regconfig, name::text))
    "index_taxa_origins" gin (to_tsvector('simple'::regconfig, origin::text))
    "index_taxa_release" gin (to_tsvector('simple'::regconfig, release::text))
    "index_taxa_taxon_id" btree (taxon_id)
    "index_taxa_version" gin (to_tsvector('simple'::regconfig, version::text))
```

---

# observations

```sql
ibrida-v0-r1=# \d observations
                          Table "public.observations"
       Column        |          Type          | Collation | Nullable | Default
---------------------+------------------------+-----------+----------+---------
 observation_uuid    | uuid                   |           | not null |
 observer_id         | integer                |           |          |
 latitude            | numeric(15,10)         |           |          |
 longitude           | numeric(15,10)         |           |          |
 positional_accuracy | integer                |           |          |
 taxon_id            | integer                |           |          |
 quality_grade       | character varying(255) |           |          |
 observed_on         | date                   |           |          |
 anomaly_score       | numeric(15,6)          |           |          |
 geom                | geometry               |           |          |
 origin              | character varying(255) |           |          |
 version             | character varying(255) |           |          |
 release             | character varying(255) |           |          |
Indexes:
    "idx_observations_anomaly" btree (anomaly_score)
    "index_observations_observer_id" btree (observer_id)
    "index_observations_origins" gin (to_tsvector('simple'::regconfig, origin::text))
    "index_observations_quality" btree (quality_grade)
    "index_observations_release" gin (to_tsvector('simple'::regconfig, release::text))
    "index_observations_taxon_id" btree (taxon_id)
    "index_observations_version" gin (to_tsvector('simple'::regconfig, version::text))
    "observations_geom" gist (geom)
```

---

# photos

```sql
ibrida-v0-r1=# \d photos
                           Table "public.photos"
      Column      |          Type          | Collation | Nullable | Default
------------------+------------------------+-----------+----------+---------
 photo_uuid       | uuid                   |           | not null |
 photo_id         | integer                |           | not null |
 observation_uuid | uuid                   |           | not null |
 observer_id      | integer                |           |          |
 extension        | character varying(5)   |           |          |
 license          | character varying(255) |           |          |
 width            | smallint               |           |          |
 height           | smallint               |           |          |
 position         | smallint               |           |          |
 origin           | character varying(255) |           |          |
 version          | character varying(255) |           |          |
 release          | character varying(255) |           |          |
Indexes:
    "index_photos_observation_uuid" btree (observation_uuid)
    "index_photos_origins" gin (to_tsvector('simple'::regconfig, origin::text))
    "index_photos_photo_id" btree (photo_id)
    "index_photos_photo_uuid" btree (photo_uuid)
    "index_photos_position" btree ("position")
    "index_photos_release" gin (to_tsvector('simple'::regconfig, release::text))
    "index_photos_version" gin (to_tsvector('simple'::regconfig, version::text))
```

---

# observers

```sql
ibrida-v0-r1=# \d observers
                       Table "public.observers"
   Column    |          Type          | Collation | Nullable | Default
-------------+------------------------+-----------+----------+---------
 observer_id | integer                |           | not null |
 login       | character varying(255) |           |          |
 name        | character varying(255) |           |          |
 origin      | character varying(255) |           |          |
 version     | character varying(255) |           |          |
 release     | character varying(255) |           |          |
Indexes:
    "index_observers_observers_id" btree (observer_id)
    "index_observers_origins" gin (to_tsvector('simple'::regconfig, origin::text))
    "index_observers_release" gin (to_tsvector('simple'::regconfig, release::text))
    "index_observers_version" gin (to_tsvector('simple'::regconfig, version::text))
```