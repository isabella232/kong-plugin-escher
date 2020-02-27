local Object = require "classic"

local function identity(entity)
    return entity
end

local CacheWarmer = Object:extend()

function CacheWarmer:new(ttl)
    self.ttl = ttl
end

function CacheWarmer:cache_all_entities(dao, key_retriever)
    local page_size = 1000
    for entity, err in dao:each(page_size) do
        assert(entity, err)
        local identifiers = key_retriever(entity)
        local cache_key = dao:cache_key(table.unpack(identifiers))

        kong.cache:get(cache_key, { ttl = self.ttl }, identity, entity)
    end
end

return CacheWarmer
