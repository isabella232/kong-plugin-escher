local Object = require "classic"

local singletons = require "kong.singletons"

local function iterate_pages(dao)
    local page_size = 1000

    local from = 1
    local current_page = dao:find_page(nil, from, page_size)
    local index_on_page = 1

    return function()
        while #current_page > 0 do
            local element = current_page[index_on_page]

            if element then
                index_on_page = index_on_page + 1
                return element
            else
                from = from + page_size
                current_page = dao:find_page(nil, from, page_size)
                index_on_page = 1
            end
        end

        return nil
    end
end

local function identity(entity)
    return entity
end

local CacheWarmer = Object:extend()

function CacheWarmer:new(ttl)
    self.ttl = ttl
end

function CacheWarmer:cache_all_entities(dao, key_retriever)
    for entity in iterate_pages(dao) do
        local identifiers = key_retriever(entity)
        print(table.unpack(identifiers))
        local cache_key = dao:cache_key(table.unpack(identifiers))

        singletons.cache:get(cache_key, { ttl = self.ttl }, identity, entity)
    end
end

return CacheWarmer
