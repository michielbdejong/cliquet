CREATE OR REPLACE FUNCTION generate_records(nb_users INTEGER,
                                            nb_collections_per_user INTEGER,
                                            nb_records_per_collection INTEGER)
RETURNS TABLE (user_id TEXT,
               collection_id TEXT,
               data JSON) AS $$
BEGIN
    RETURN QUERY
        WITH users AS (
            SELECT 'fake_' || generate_series(1, nb_users) AS id
        ),
        collections AS (
            SELECT 'collection_' || generate_series(1, nb_collections_per_user) AS id
        ),
        records AS (
            SELECT ('{"name": "mushroom", "value": ' || generate_series(1, nb_records_per_collection) || '}')::JSON AS data
        )
        SELECT users.id, collections.id, records.data
        FROM users, collections, records;
END;
$$ LANGUAGE plpgsql;

--
-- Usage:
--
--  INSERT INTO records(user_id, resource_name, data)
--      SELECT * FROM generate_records(10000, 3, 10);
--
--  INSERT INTO deleted(user_id, resource_name)
--      SELECT user_id, collection_id FROM generate_records(10000, 3, 10);
--
