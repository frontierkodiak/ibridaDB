These tools are for ingesting old `anthophila` data into ibridaDB. `anthophila` is directory structure with per-taxon subdirs, each containing images (I think we don't have the original metadata).
    Anthophila data originates from several sources, inc. Xerces society, iNat, and some old dumps of licensed images. This is in contrast to the rest of our ibrida data, which is exclusively from iNat. Because of this, we need to do careful curation of the data to prevent duplicates + recover (at minimum) the taxonomic information for each image.
This is a messy data, but `anthophila` is ultimately a very high-value dataset because bees are the single most important clade for our product + for our pollination lab clients.
Our goal is to bring the anthophila data into ibridaDB `observations` table. Unless we find a metadata table, we're only going to be able to get image + taxon information; timestamp, location, etc. are not available. Once the data is in the `observations` table, these data will be available for training dataset generation, just like any other samples in `observations`.
    There will be a handful of follow-up steps to be able to use the new data for training datasets.
        Most notably the anthophila images are on the local filesystem (not on iNat-Open-Data S3 bucket), so we'll file a ticket on ibrida.generator to support fetching images from local fs.
        This shouldn't be too difficult to implement, so long as we have a way to determine whether a sample is local or not.. `observations` has an `origin` column which we should use for this purpose. We need to query to see what `origin` value is in-place for the existing rows (should only be a single value, I think it's something like iNat Dec 2024). For the new data, we can set something like `anthophila generic Aug 2025` (or something like that, re-evaluate after identifying the origin value for existing data).
Assuming that we can't find original metadata, we need to figure out how to:
• Get taxonomic information for each image
    - This is pretty easy. We can use typus, I think we provide a way to get taxon_id from scientific name. We just need to strip underscore from dirnames (e.g. `genus_species` -> `genus species`? double-check typus interface); then we should also sanity-check by verifying that the rank_level is correct (a simple rule of thumb is that two-word dirnames are always species, i.e. L10, three-word dirnames are subspecies, i.e. L5, one-word dirnames could be anything higher than species, so L11 above-- *most* should be genus, L20). taxon_id is all we need.
• Reject `anthophila` images that are already in the `observations` table. This is effectively equivalent to rejecting `anthophila` images originate from iNat; we only want to ingest new data from anthophila (which come from a myriad of third-party sources). Now, how should we do this?
    - What information is encoded in the image filenames? It seems like the filenames (all of them?) are of the form `Osmia_chalybea_10421352_1.jpg`, so what is the `10421352` representing here? Does this relate to `photos.photo_id`?
        - Yes, at least in some cases. `https://www.inaturalist.org/observations/10421352` is an observation of `Osmia chalybea`, so for this image, we would reject b/c it originates from iNat (and by defn *should* already be represented in the `observations` table).
        - We need to rigorously study the `anthophila` filenames to determine if this is a reliable way to identify iNat images. It's possible that I am misremembering the `anthophila` data, and that all (or a very large fraction) of the images are from iNat, in which case this entire process is moot. So let's `fail quickly`; our first step must be to measure the proportion of `anthophila` images that are from iNat, if >90% then let's not waste our time on this process.

Considerations (some of these could break assumptions from our existing data pipeline, especially export scripts):
• `observation_uuid` will be null for all new non-iNat data (i.e. the `anthophila` data that we want to ingest). Does anything break if this is null?
• `quality_grade` -- let's just set to `research` for all accepted new data. these are very high-quality expert labels.
Other columns that won't be available (nulls/sentinels for these *shouldn't* be breaking, but we should double-check, and then of course be smart with what we do for the null/sentinel; this is an important decision):
• `observer_id`
• `latitude`
• `longitude`
• `positional_accuracy`
• `observed_on`
• `anomaly_score`
• `geom`
• `origin`
• `version` -- we'll set to `v0`
• `release` -- `r1` or `r2` ? need to decide

