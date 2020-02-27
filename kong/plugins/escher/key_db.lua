local Logger = require "logger"
local Object = require "classic"

local KeyDb = Object:extend()

local function load_credential(key)
    local escher_keys, err = kong.db.connector:query(string.format("SELECT * FROM escher_keys WHERE key = '%s'", key))
    if err then
        return nil, err
    end

    return escher_keys[1]
end

function KeyDb:new(crypto)
    self.crypto = crypto
end

function KeyDb:find_secret_by_key(key)
    local escher_key = self:find_by_key(key)

    if not escher_key then
      return nil
    end

    return self.crypto:decrypt(escher_key.secret)
end

function KeyDb:find_by_key(key)
    local cache_key = kong.db.escher_keys:cache_key(key)
    local escher_key, err = kong.cache:get(cache_key, nil, load_credential, key)

    if err then
      Logger.getInstance(ngx):logError(err)
      return nil
    end

    if not escher_key then
      Logger.getInstance(ngx):logWarning({msg = "Escher key was not found."})
      return nil
    end

    return escher_key
end

return KeyDb
