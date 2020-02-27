local Logger = require "logger"
local Object = require("classic")

local ConsumerDb = Object:extend()

local function load_consumer(consumer_id)
    local consumer, err = kong.db.consumers:select({ id = consumer_id })

    return consumer, err
end

function ConsumerDb.find_by_id(consumer_id)
    if not consumer_id then
        Logger.getInstance(ngx):logWarning({ msg = "Consumer id is required." })
        error({ msg = "Consumer id is required." })
    end

    local cache_key = kong.db.consumers:cache_key(consumer_id)
    local consumer, err = kong.cache:get(cache_key, nil, load_consumer, consumer_id)

    if err then
        Logger.getInstance(ngx):logError(err)
        error(err)
    end

    if not consumer then
        Logger.getInstance(ngx):logWarning({ msg = "Consumer can not be found." })
        error({ msg = "Consumer can not be found." })
    end

    return consumer
end

return ConsumerDb
