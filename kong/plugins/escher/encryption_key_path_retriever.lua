local Object = require "classic"

local EncryptionKeyPathRetriever = Object:extend()

function EncryptionKeyPathRetriever:new(db)
    self.db = db
end

function EncryptionKeyPathRetriever:find_key_path()
    local escher_plugins, err = self.db.connector:query(string.format("SELECT * FROM plugins WHERE name = '%s' LIMIT 1", "escher"))
    if err then
        return nil, err
    end

    if not escher_plugins[1] then
        return nil
    end

    return escher_plugins[1].config.encryption_key_path
end

return EncryptionKeyPathRetriever