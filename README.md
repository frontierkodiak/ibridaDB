# ibridaDB

## Build Image

This project requires the use of the `raster2pgsql` CLI tool for importing DEM data. The official PostGIS Docker image (e.g. `postgis/postgis:15-3.3`) does not include this command by default in its runtime environment. Therefore, we extend the official image by installing the PostGIS package (which contains `raster2pgsql`) and copying the binary into the final image.

### Steps to Build and Push the Custom Image

1. **Build the image:**

   ```bash
   cd ~/repo/ibridaDB/docker && docker build -t frontierkodiak/ibridadb:latest .
   ```

2. **Push the image to Docker Hub:**

   Make sure you’re logged in as user `frontierkodiak`:

   ```bash
   docker login
   docker push frontierkodiak/ibridadb:latest
   ```

```bash
cd ~/repo/ibridaDB/docker && docker build -t frontierkodiak/ibridadb:latest . --no-cache && docker push frontierkodiak/ibridadb:latest
```

This image will be used in our docker-compose configuration to run the ibridaDB instance with the required raster CLI tools available.