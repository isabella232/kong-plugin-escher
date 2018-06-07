local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local KeyDb = require "kong.plugins.escher.key_db"
local Logger = require "logger"
local Crypt = require "kong.plugins.escher.crypt"


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

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
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
            local error_message = "X-EMS-AUTH header not found!"
            Logger.getInstance(ngx):logInfo({status = 401, msg = error_message})
            return responses.send(401, error_message)
        end
    end)

    if not success then
        Logger.getInstance(ngx).logError(result)
        return responses.send(500, "An unexpected error occurred.")
    end

    return result
end

return EscherHandler
