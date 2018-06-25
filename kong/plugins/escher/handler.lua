local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local KeyDb = require "kong.plugins.escher.key_db"
local Logger = require "logger"
local Crypt = require "kong.plugins.escher.crypt"
local singletons = require "kong.singletons"


local EscherHandler = BasePlugin:extend()

EscherHandler.PRIORITY = 1007

local function set_consumer(consumer, escher_key)
    ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    ngx.ctx.authenticated_consumer = consumer

    if escher_key then
        ngx.req.set_header(constants.HEADERS.CREDENTIAL_USERNAME, escher_key.key)
        ngx.req.set_header(constants.HEADERS.ANONYMOUS, nil)
        ngx.ctx.authenticated_credential = escher_key
    else
        ngx.req.set_header(constants.HEADERS.ANONYMOUS, true)
    end
end

local function anonymous_passthrough_is_enabled(plugin_config)
    return plugin_config.anonymous ~= nil
end

local function already_authenticated_by_other_plugin(plugin_config, authenticated_credential)
    return anonymous_passthrough_is_enabled(plugin_config) and authenticated_credential ~= nil
end

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

local function cache_all_entities_in(dao, key_retriever)
    for entity in iterate_pages(dao) do
        local unique_identifier = key_retriever(entity)
        local cache_key = dao:cache_key(unique_identifier)
        
        singletons.cache:get(cache_key, nil, identity, entity)
    end
end

local function retrieve_id_from_consumer(consumer)
    return consumer.id
end

local function retrieve_escher_key_name(escher_key)
    return escher_key.key
end

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
end

function EscherHandler:init_worker()
    EscherHandler.super.init_worker(self)

    cache_all_entities_in(singletons.dao.consumers, retrieve_id_from_consumer)
    cache_all_entities_in(singletons.dao.escher_keys, retrieve_escher_key_name)
end

function EscherHandler:access(conf)
    EscherHandler.super.access(self)

    if already_authenticated_by_other_plugin(conf, ngx.ctx.authenticated_credential) then
        return
    end

    local success, result = pcall(function()
        local crypt = Crypt(conf.encryption_key_path)
        local key_db = KeyDb(crypt)
        local escher = EscherWrapper(ngx, key_db)
        local escher_key, err = escher:authenticate()

        if escher_key then
            local consumer = ConsumerDb.find_by_id(escher_key.consumer_id)

            set_consumer(consumer, escher_key)
            Logger.getInstance(ngx):logInfo({msg = "Escher authentication was successful."})
        elseif anonymous_passthrough_is_enabled(conf) then
            local anonymous = ConsumerDb.find_by_id(conf.anonymous, true)
            set_consumer(anonymous)
            Logger.getInstance(ngx):logInfo({msg = "Escher authentication skipped."})
        else
            Logger.getInstance(ngx):logInfo({status = 401, msg = err})
            return responses.send(401, err)
        end
    end)

    if not success then
        Logger.getInstance(ngx).logError(result)
        return responses.send(500, "An unexpected error occurred.")
    end

    return result
end

return EscherHandler
