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

UPDATE metadata SET value = '3' WHERE name = 'storage_schema_version';
