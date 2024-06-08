This table contains the full taxonomy (inc. full ancestral) for each taxa. This is an expanded version of the 'taxa' table.
    Note that this table is less space-efficient than the 'taxa' table, but it is more convenient to use.

This table is created to mimic the existing redis-taxa-legacy table.
Note that there are syntax differences between this table and the 'taxa' table.

Base 'taxa' table syntax (from iNat):
```
CREATE TABLE taxa (
    taxon_id integer NOT NULL,
    ancestry character varying(255),
    rank_level double precision,
    rank character varying(255),
    name character varying(255),
    active boolean
);
```

Differences:
- taxon_id -> taxonID
- rank_level -> rank