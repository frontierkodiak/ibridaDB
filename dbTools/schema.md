```markdown
### Observations
Column | Description
-------|------------
observation_uuid | A unique identifier associated with each observation also available at iNaturalist.org via URLs constructed like this https://www.inaturalist.org/observations/c075c500-b566-44aa-847c-95da8fb8b3c9
observer_id | The identifier of the associated iNaturalist user who recorded the observation
latitude | The latitude where the organism was encountered
longitude | The longitude where the organism was encountered
positional_accuracy | The uncertainty in meters around the latitude and longitude
taxon_id | The identifier of the associated axon the observation has been identified as
quality_grade | `Casual` observations are missing certain data components (e.g. latitude) or may have flags associated with them not shown here (e.g. `location appears incorrect`). Observations flagged as not wild are also considered Casual. All other observations are either `Needs ID` or `Research Grade`. Generally, Research Grade observations have more than one agreeing identifications at the species level, or if there are disagreements at least ⅔ of the identifications are in agreement a the species level
observed_on | The date at which the observation took place
<NOTE> New column added in v0/r1 'anomaly_score' </NOTE>

### Observers
Column | Description
-------|------------
observer_id | A unique identifier associated with each observer also available on https://www.inaturalist.org via URLs constructed like this: https://www.inaturalist.org/users/1
login | A unique login associated with each observer
name | Personal name of the observer, if provided

### Photos
Column | Description
-------|------------
photo_uuid | A unique identifier associated with each photo. Note that photo_uuid can be non-unique across different observations.
photo_id | A photo identifier used on iNaturalist and available on iNaturalist.org via URLs constructed like this https://www.inaturalist.org/photos/113756411
observation_uuid | The identifier of the associated observation
observer_id | The identifier of the associated observer who took the photo
extension | The image file format, e.g. `jpeg`
license | All photos in the dataset have open licenses (e.g. Creative Commons) and unlicensed (CC0 / public domain)
width | The width of the photo in pixels
height | The height of the photo in pixels
position | When observations have multiple photos the user can set the position in which the photos should appear. Lower numbers are meant to appear first
>The issue is that some observations include more than one photo, and photos associated with observations that have >1 photo share a photo_id and photo_uuid, which I did not expect. These additional photos (which have their own rows in the 'photos' table) are denoted by the 'position' field, where position ==0 indicates that the photo is the primary photo for the record. If an observation only has one photo, then the associated 'photos' record will have position == 0. Therefore. I'm pretty sure that a composite key of photo_id ++ photo_uuid ++ position will function as a primary key. 

### Taxa
Column | Description
-------|------------
taxon_id | A unique identifier associated with each node in the iNaturalist taxonomy hierarchy. Also available on iNaturalist.org via URLs constructed like this https://www.inaturalist.org/taxa/47219
ancestry | The taxon_ids of ancestry of the taxon ordered from the root of the tree to the taxon concatenated together with `\`
rank_level | A number associated with the rank. Taxon rank_levels must be less than the rank level of their parent. For example, a taxon with rank genus and rank_level 20 cannot descend from a taxon of rank species and rank_level 10
rank | A constrained set of labels associated with nodes on the hierarchy. These include the standard Linnaean ranks: Kingdom, Phylum, Class, Order, Family, Genus, Species, and a number of internodes such as Subfamily
name | The scientific name for the taxon
active | When the taxonomy changes, generally taxa aren’t deleted on iNaturalist to avoid breaking links. Instead taxa are made inactive and observations are moved to new active nodes. Occasionally, observations linger on inactive taxa which are no longer active parts of the iNaturalist taxonomy
```