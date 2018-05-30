local singletons = require "kong.singletons"
local Object = require("classic")
local Logger = require "logger"

local EasyCrypto = require "resty.easy-crypto"

local ecrypto = EasyCrypto:new({
    saltSize = 12,
    ivSize = 16,
    iterationCount = 10000
})

local function get_encryption_key(encryption_key_path)
    local file = assert(io.open(encryption_key_path, "r")) -- TEST
    local encryption_key = file:read("*all")

    file:close()
    return encryption_key
end

local KeyDb = Object:extend()

local function load_credential(key)
    local credential, err = singletons.dao.escher_keys:find_all { key = key }

    if err then
        return nil, err
    end

    return credential[1]
end

function KeyDb:find_secret_by_key(key)
    local escher_key = self:find_by_key(key)

    if not escher_key then
      return nil
    end

    local encryption_key = get_encryption_key('/secret.txt')

    return ecrypto:decrypt(encryption_key, escher_key.secret)
end

function KeyDb:find_by_key(key)
    local escher_cache_key = singletons.dao.escher_keys:cache_key(key)
    local escher_key, err = singletons.cache:get(escher_cache_key, nil, load_credential, key)

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