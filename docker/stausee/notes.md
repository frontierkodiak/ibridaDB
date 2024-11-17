Moving the ibrida psql database to stausee-pool's 'database' dataset.
    'database' dataset is tuned for performance with psql:
```md
3. `stausee-pool/database` (Database Storage):
   - Purpose: PostgreSQL database files
   - Optimizations:
     - recordsize=8K: Matches database page size
     - logbias=latency: Optimized for write performance
     - sync=standard: Ensures data integrity
     - quota=2T: Controlled growth
   - Best for:
     - PostgreSQL data directory
     - High-IOPS workloads
     - Transaction-heavy applications
```
Note that the 'database' dataset is mounted at `mango/database` .

Let's move the ibrida database to the 'database' dataset (replacing the peach mount `/peach/ibrida2:/var/lib/postgresql/data`) to free up space on peach (which is valuable nvme storage).
    Performance penalty shouldn't be too bad given the specific tuning of the 'database' dataset.

Edit other bind mounts to use stausee-pool's `datasets` dataset (mounted at `/mango/datasets`).
    Migrate bind mounts:
    - `/pond/Polli/ibridaExports:/exports` -> `/mango/datasets/ibrida-data/exports:/exports`
    - `/ibrida/metadata:/metadata` -> `/mango/datasets/ibrida-data/intake:/metadata`
    - `/peach/ibrida2:/var/lib/postgresql/data` -> `/mango/database/ibridaDB:/var/lib/postgresql/data`