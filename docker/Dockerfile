# syntax=docker/dockerfile:1
#
# Dockerfile for extending the official PostGIS image with raster2pgsql.
# This multi-stage build installs the PostGIS package (which includes
# raster2pgsql) in a builder stage, then copies the raster2pgsql binary
# into the final image.
#
# The final image is based on postgis/postgis:15-3.3 and will be tagged as
# frontierkodiak/ibridaDB:latest.
#

##########################
# Stage 1: Builder
##########################
FROM postgis/postgis:15-3.3 AS builder
USER root

# Update apt and install postgis package to obtain the CLI tools.
RUN apt-get update && apt-get install -y postgis

# Verify that raster2pgsql is installed (should appear in /usr/bin)
RUN which raster2pgsql

##########################
# Stage 2: Final Image
##########################
FROM postgis/postgis:15-3.3

# Copy the raster2pgsql binary from the builder stage into /usr/bin.
# Adjust the path if your distribution installs it elsewhere.
COPY --from=builder /usr/bin/raster2pgsql /usr/bin/raster2pgsql

# (Optional) Ensure correct permissions (if necessary)
USER postgres

# By default, no CMD is defined; the official entrypoint of the base image
# will be used.
