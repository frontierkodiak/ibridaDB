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
Note that the 'database' dataset is mounted at `mango/database` (`/database` lns here).