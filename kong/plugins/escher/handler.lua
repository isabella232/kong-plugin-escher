local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local cjson = require "cjson"
local KeyDb = require "kong.plugins.escher.key_db"
local Logger = require "logger"
local Crypt = require "kong.plugins.escher.crypt"
local InitWorker = require "kong.plugins.escher.init_worker"
local PluginConfig = require "kong.plugins.escher.plugin_config"
local schema = require "kong.plugins.escher.schema"


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

local function get_transformed_response(template, response_message)
    return cjson.decode(string.format(template, response_message))
end

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
end

function EscherHandler:init_worker()
    EscherHandler.super.init_worker(self)

    InitWorker.execute()
end

function EscherHandler:access(original_config)
    EscherHandler.super.access(self)

    local conf = PluginConfig(schema):merge_onto_defaults(original_config)

    if already_authenticated_by_other_plugin(conf, ngx.ctx.authenticated_credential) then
        return
    end

    local success, result = pcall(function()
        local crypt = Crypt(conf.encryption_key_path)
        local key_db = KeyDb(crypt)
        local escher = EscherWrapper(ngx, key_db)
        local escher_key, err = escher:authenticate()
        local headers = ngx.req.get_headers()

        if escher_key then
            local consumer = ConsumerDb.find_by_id(escher_key.consumer_id)

            set_consumer(consumer, escher_key)
            Logger.getInstance(ngx):logInfo({msg = "Escher authentication was successful.", ["x-ems-auth"] = headers['x-ems-auth']})
        elseif anonymous_passthrough_is_enabled(conf) then
            local anonymous = ConsumerDb.find_by_id(conf.anonymous, true)
            set_consumer(anonymous)
            Logger.getInstance(ngx):logWarning({msg = "Escher authentication skipped.", ["x-ems-auth"] = headers['x-ems-auth']})
        else
            local status_code = conf.status_code

            Logger.getInstance(ngx):logWarning({status = status_code, msg = err, ["x-ems-auth"] = headers['x-ems-auth']})

            return responses.send(status_code, get_transformed_response(conf.message_template, err))
        end
    end)

    if not success then
        Logger.getInstance(ngx):logError(result)
        return responses.send(500, "An unexpected error occurred.")
    end

    return result
end

return EscherHandler
