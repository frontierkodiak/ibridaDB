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
- commonName -> common_name

### Special Handling of Sparse Integer Columns
In the `taxa_expanded` table, several integer columns are sparse and may not always contain data. To handle this, we use `-1` as a placeholder for null or missing values in these columns. This approach allows us to maintain integer data types across the database while clearly indicating the absence of data.

#### Columns Using -1 for Null Values:
- L5_taxon_id
- L10_taxon_id
- L11_taxon_id
- ... (list all other relevant columns)

It is crucial for downstream scripts and data processing logic to treat `-1` as equivalent to null. This ensures consistency in data handling and analysis.


Drop-in is_null method:
```python
def is_null(value):
    """
    Check if the provided value should be considered null.

    This function is designed to handle cases where `-1` is used as a placeholder
    for null values in integer columns of a database. It returns True if the value
    is `-1` or None, treating both as null.

    Known usecases:
        downstream of taxaDB.taxa-expanded:
            - flagging '-1' as null for ancestral taxon_id columns.

    Parameters:
    - value (int): The value to check.

    Returns:
    - bool: True if the value is null, False otherwise.
    """
    return value == -1 or value is None
```