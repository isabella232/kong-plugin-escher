local Object = require "classic"

local singletons = require "kong.singletons"

local function iterate_pages(dao)
        local page_size = 1000

        local current_page, err, err_t, next_page
        local items_on_page = 0
        local index_on_page = 1

        return function()
            if index_on_page > items_on_page and (next_page or not current_page) then
                current_page, err, err_t, next_page = dao:find_page(nil, next_page, page_size)

                assert(current_page, err)

                items_on_page = #current_page
                index_on_page = 1
            end

            local item = current_page[index_on_page]

            index_on_page = index_on_page + 1

            return item
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
        local cache_key = dao:cache_key(table.unpack(identifiers))

        singletons.cache:get(cache_key, { ttl = self.ttl }, identity, entity)
    end
end

return CacheWarmer
