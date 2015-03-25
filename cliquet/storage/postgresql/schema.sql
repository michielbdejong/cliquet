--
-- Load pgcrypto for UUID generation
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- Metadata table
--
CREATE TABLE IF NOT EXISTS metadata (
    name VARCHAR(128) NOT NULL,
    value VARCHAR(512) NOT NULL
);
INSERT INTO metadata (name, value) VALUES ('created_at', NOW()::TEXT);


--
-- Convert timestamps to integer
--
CREATE OR REPLACE FUNCTION as_epoch(ts TIMESTAMP) RETURNS BIGINT AS $$
BEGIN
    RETURN (EXTRACT(EPOCH FROM ts) * 1000)::BIGINT;
END;
$$ LANGUAGE plpgsql
IMMUTABLE;

--
-- Actual records
--
CREATE TABLE IF NOT EXISTS records (
    id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id VARCHAR(256) NOT NULL,
    resource_name  VARCHAR(256) NOT NULL,
    last_modified TIMESTAMP NOT NULL,
    data JSON NOT NULL DEFAULT '{}',
    UNIQUE (id, user_id, resource_name, last_modified)
);
DROP INDEX IF EXISTS idx_records_user_id;
CREATE INDEX idx_records_user_id ON records(user_id);
DROP INDEX IF EXISTS idx_records_resource_name;
CREATE INDEX idx_records_resource_name ON records(resource_name);
DROP INDEX IF EXISTS idx_records_last_modified;
CREATE INDEX idx_records_last_modified ON records(last_modified);
DROP INDEX IF EXISTS idx_records_last_modified_epoch;
CREATE INDEX idx_records_last_modified_epoch ON records(as_epoch(last_modified));
DROP INDEX IF EXISTS idx_records_id;
CREATE INDEX idx_records_id ON records(id);


--
-- Deleted records
--
CREATE TABLE IF NOT EXISTS deleted (
    id UUID,
    user_id VARCHAR(256) NOT NULL,
    resource_name  VARCHAR(256) NOT NULL,
    last_modified TIMESTAMP NOT NULL,
    UNIQUE (id, user_id, resource_name, last_modified)
);
DROP INDEX IF EXISTS idx_deleted_id;
CREATE UNIQUE INDEX idx_deleted_id ON deleted(id);
DROP INDEX IF EXISTS idx_deleted_user_id;
CREATE INDEX idx_deleted_user_id ON deleted(user_id);
DROP INDEX IF EXISTS idx_deleted_resource_name;
CREATE INDEX idx_deleted_resource_name ON deleted(resource_name);
DROP INDEX IF EXISTS idx_deleted_last_modified;
CREATE INDEX idx_deleted_last_modified ON deleted(last_modified);
DROP INDEX IF EXISTS idx_deleted_last_modified_epoch;
CREATE INDEX idx_deleted_last_modified_epoch ON deleted(as_epoch(last_modified));

--
-- Helpers
--
CREATE OR REPLACE FUNCTION resource_timestamp(uid VARCHAR, resource VARCHAR)
RETURNS TIMESTAMP AS $$
DECLARE
    ts TIMESTAMP;
BEGIN
    SELECT last_modified INTO ts
      FROM view_collection_timestamp
     WHERE user_id = uid AND resource_name = resource;

    RETURN coalesce(ts, localtimestamp);
END;
$$ LANGUAGE plpgsql;

--
-- Triggers to set last_modified on INSERT/UPDATE
--
DROP TRIGGER IF EXISTS tgr_records_last_modified ON records;
DROP TRIGGER IF EXISTS tgr_deleted_last_modified ON deleted;

CREATE OR REPLACE FUNCTION bump_timestamp()
RETURNS trigger AS $$
DECLARE
    previous TIMESTAMP;
    current TIMESTAMP;
BEGIN
    previous := resource_timestamp(NEW.user_id, NEW.resource_name);
    current := localtimestamp;

    IF previous >= current THEN
        current := previous + INTERVAL '1 milliseconds';
    END IF;

    NEW.last_modified := current;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tgr_records_last_modified
BEFORE INSERT OR UPDATE ON records
FOR EACH ROW EXECUTE PROCEDURE bump_timestamp();

CREATE TRIGGER tgr_deleted_last_modified
BEFORE INSERT OR UPDATE ON deleted
FOR EACH ROW EXECUTE PROCEDURE bump_timestamp();

--
-- Use a materialized view to cache collection timestamps.
--
DROP MATERIALIZED VIEW IF EXISTS view_collection_timestamp CASCADE;
CREATE MATERIALIZED VIEW view_collection_timestamp AS (
    WITH ts_records AS (
        SELECT user_id, resource_name, MAX(last_modified) AS last_modified
          FROM records
          GROUP BY user_id, resource_name
    ),
    ts_deleted AS (
        SELECT user_id, resource_name, MAX(last_modified) AS last_modified
          FROM records
          GROUP BY user_id, resource_name
    ),
    ts_records_delete AS (
        SELECT r.user_id, r.resource_name,
               greatest(r.last_modified, d.last_modified) AS last_modified
          FROM ts_records AS r JOIN ts_deleted AS d
            ON (r.user_id = d.user_id AND r.resource_name = d.resource_name)
    )
    SELECT user_id, resource_name, last_modified
      FROM ts_records_delete
);
CREATE UNIQUE INDEX idx_view_collection_timestamp ON view_collection_timestamp (user_id, resource_name);

DROP TRIGGER IF EXISTS tgr_records_refresh_collection_timestamp ON records;
DROP TRIGGER IF EXISTS tgr_deleted_refresh_collection_timestamp ON deleted;

CREATE OR REPLACE FUNCTION refresh_collection_timestamp()
RETURNS trigger AS $$
BEGIN
    REFRESH MATERIALIZED VIEW view_collection_timestamp;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tgr_records_refresh_collection_timestamp
AFTER INSERT OR UPDATE ON records
FOR EACH ROW EXECUTE PROCEDURE refresh_collection_timestamp();

CREATE TRIGGER tgr_deleted_refresh_collection_timestamp
AFTER INSERT OR UPDATE ON deleted
FOR EACH ROW EXECUTE PROCEDURE refresh_collection_timestamp();


-- Set storage schema version.
-- Should match ``cliquet.storage.postgresql.PostgreSQL.schema_version``
INSERT INTO metadata (name, value) VALUES ('storage_schema_version', '3');
