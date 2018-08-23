local CacheWarmer = require 'kong.plugins.escher.cache_warmer'

local singletons = require "kong.singletons"

local function retrieve_id_from_consumer(consumer)
    return { consumer.id }
end

local function retrieve_escher_key_name(escher_key)
    return { escher_key.key }
end

local ONE_DAY_IN_SECONDS = 86400

local InitWorker = {}

InitWorker.execute = function()
    local cache_warmer = CacheWarmer(ONE_DAY_IN_SECONDS)

    cache_warmer:cache_all_entities(singletons.dao.consumers, retrieve_id_from_consumer)
    cache_warmer:cache_all_entities(singletons.dao.escher_keys, retrieve_escher_key_name)
end

return InitWorker

