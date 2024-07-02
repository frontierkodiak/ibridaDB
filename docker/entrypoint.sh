# entrypoint.sh
#!/bin/bash
set -e

echo "Entrypoint script executed at $(date)" >> /var/log/entrypoint.log
echo "Entrypoint script executed at $(date)"

# Adjust permissions
chmod -R 777 /exports
chown -R postgres:postgres /exports

# Start PostgreSQL
docker-entrypoint.sh postgres
