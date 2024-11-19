#!/bin/bash
set -e

# Just log and exit - let Docker's default entrypoint handle PostgreSQL
echo "Entrypoint script executed at $(date)"