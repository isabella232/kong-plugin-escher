return {
    {
        name = "2018-04-05-110000_init_escher_keys",
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
            ]],
        down = [[
              DROP TABLE escher_keys;
            ]]
    }
}