# syntax=docker/dockerfile:1
#
# Dockerfile for extending the official PostGIS image with raster2pgsql.
# The official image (postgis/postgis:15-3.3) does not include the CLI tools
# (like raster2pgsql) by default in its runtime environment.
# This multi-stage build installs the PostGIS package (which provides the CLI tools)
# in a builder stage and then copies the raster2pgsql binary from /usr/bin in the builder
# into /usr/bin in the final image.
#
# Build and tag the image as:
#   docker build -t frontierkodiak/ibridadb:latest ./docker
#
# Then push it to Docker Hub:
#   docker login
#   docker push frontierkodiak/ibridadb:latest
#

##########################
# Stage 1: Builder
##########################
FROM postgis/postgis:15-3.3 AS builder
USER root

# Update apt and install the postgis package (which provides raster2pgsql).
RUN apt-get update && \
    apt-get install -y postgis && \
    rm -rf /var/lib/apt/lists/*

# Confirm location of raster2pgsql.
# On our system, it is installed in /usr/bin.
RUN which raster2pgsql || true

##########################
# Stage 2: Final Image
##########################
FROM postgis/postgis:15-3.3
USER root

# Copy the raster2pgsql binary from the builder stage.
COPY --from=builder /usr/bin/raster2pgsql /usr/bin/raster2pgsql

# Ensure the binary is executable.
RUN chmod +x /usr/bin/raster2pgsql

# Switch to the default postgres user.
USER postgres
