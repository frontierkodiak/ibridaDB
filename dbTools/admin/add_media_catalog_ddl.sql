-- DDL for generic media catalog + observation_media junction
-- IBRIDA-006: Add media catalog (URIs) + observation_media junction

-- Create media table for non-iNat assets (anthophila, etc.)
CREATE TABLE IF NOT EXISTS media (
    media_id BIGSERIAL PRIMARY KEY,
    dataset VARCHAR(64) NOT NULL,           -- e.g., 'anthophila', 'gbif', etc.
    release VARCHAR(16) NOT NULL,           -- e.g., 'r2'
    source_tag VARCHAR(128),                -- e.g., 'expert-taxonomist', 'museum-specimen'
    uri TEXT NOT NULL UNIQUE,               -- file://, b2://, s3://, https:// URIs
    sha256_hex CHAR(64) UNIQUE,            -- SHA-256 hash for deduplication
    phash_64 BIGINT,                       -- perceptual hash for near-duplicate detection
    width_px INTEGER,                      -- image width in pixels
    height_px INTEGER,                     -- image height in pixels
    mime_type VARCHAR(64),                 -- e.g., 'image/jpeg', 'image/png'
    file_bytes BIGINT,                     -- file size in bytes
    captured_at TIMESTAMP WITH TIME ZONE, -- when the photo was taken (if known)
    sidecar JSONB,                         -- additional metadata (provenance, original_path, etc.)
    license VARCHAR(128) DEFAULT 'unknown', -- license information
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create junction table linking observations to media
CREATE TABLE IF NOT EXISTS observation_media (
    observation_uuid UUID NOT NULL,
    media_id BIGINT NOT NULL,
    role VARCHAR(32) DEFAULT 'primary',    -- 'primary', 'secondary', 'specimen', etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (observation_uuid, media_id),
    FOREIGN KEY (observation_uuid) REFERENCES observations(observation_uuid) ON DELETE CASCADE,
    FOREIGN KEY (media_id) REFERENCES media(media_id) ON DELETE CASCADE
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_media_dataset_release ON media(dataset, release);
CREATE INDEX IF NOT EXISTS idx_media_sha256 ON media(sha256_hex);
CREATE INDEX IF NOT EXISTS idx_media_phash ON media(phash_64);
CREATE INDEX IF NOT EXISTS idx_media_uri_prefix ON media(uri varchar_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_media_sidecar_gin ON media USING GIN(sidecar);

CREATE INDEX IF NOT EXISTS idx_observation_media_media_id ON observation_media(media_id);
CREATE INDEX IF NOT EXISTS idx_observation_media_role ON observation_media(role);

-- Create public view excluding unknown/restricted licenses
CREATE OR REPLACE VIEW public_media AS
SELECT 
    media_id,
    dataset,
    release,
    source_tag,
    uri,
    sha256_hex,
    phash_64,
    width_px,
    height_px,
    mime_type,
    file_bytes,
    captured_at,
    sidecar,
    license,
    created_at
FROM media
WHERE license NOT IN ('unknown', 'restricted', 'all-rights-reserved')
   OR license IS NULL;

-- Grant appropriate permissions
GRANT SELECT ON media TO PUBLIC;
GRANT SELECT ON observation_media TO PUBLIC; 
GRANT SELECT ON public_media TO PUBLIC;