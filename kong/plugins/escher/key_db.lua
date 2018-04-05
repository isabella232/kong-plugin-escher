local singletons = require "kong.singletons"
local Object = require("classic")
local crypto = require "crypto"

local KeyDb = Object:extend()

local function load_credential(key)
    local credential, err = singletons.dao.escher_keys:find_all { key = key }

    if err then
        return nil, err
    end

    return credential[1]
end

function KeyDb.find_by_key(key)
    local escher_cache_key = singletons.dao.escher_keys:cache_key(key)
    local escher_key, err = singletons.cache:get(escher_cache_key, nil, load_credential, key)

    if err or not escher_key then
        return nil
    end

    return escher_key.secret
end

return KeyDb