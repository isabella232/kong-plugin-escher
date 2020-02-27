return {
    postgres = {
        up = [[
            CREATE TABLE IF NOT EXISTS escher_keys(
                id uuid,
                consumer_id uuid REFERENCES consumers (id) ON DELETE CASCADE,
                key text UNIQUE,
                secret text,
                PRIMARY KEY (id)
            );
            CREATE INDEX IF NOT EXISTS escher_keys_key_idx ON escher_keys(key);
            CREATE INDEX IF NOT EXISTS escher_keys_consumer_idx ON escher_keys(consumer_id);
        ]]
    },
    cassandra = {
        up = [[
            CREATE TABLE IF NOT EXISTS escher_keys(
                id uuid,
                consumer_id uuid,
                key text,
                secret text,
                PRIMARY KEY (id)
            );
            CREATE INDEX IF NOT EXISTS escher_keys_key_idx ON escher_keys(key);
            CREATE INDEX IF NOT EXISTS escher_keys_consumer_idx ON escher_keys(consumer_id);
        ]]
    }
}