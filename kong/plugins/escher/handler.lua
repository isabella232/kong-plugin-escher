local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local Logger = require "logger"


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

function EscherHandler:new()
    EscherHandler.super.new(self, "escher")
end

function EscherHandler:access(conf)
    EscherHandler.super.access(self)

    if ngx.ctx.authenticated_credential and conf.anonymous ~= nil then
        -- we're already authenticated, and we're configured for using anonymous,
        -- hence we're in a logical OR between auth methods and we're already done.
        return
    end

    local escher_header_string = ngx.req.get_headers()["X-EMS-AUTH"]

    if escher_header_string then
        local escher = EscherWrapper(ngx)
        local escher_key, err = escher:authenticate()

        if not escher_key then
            Logger.getInstance(ngx):logInfo({status = 401, msg = err})
            return responses.send(401, err)
        end

        local consumer = ConsumerDb.find_by_id(escher_key.consumer_id)

        set_consumer(consumer, escher_key)
        Logger.getInstance(ngx):logInfo({msg = "Escher authentication was successful."})
    elseif conf.anonymous == nil then
        local error_message = "X-EMS-AUTH header not found!"
        Logger.getInstance(ngx):logInfo({status = 401, msg = error_message})
        return responses.send(401, error_message)
    else
        local anonymous = ConsumerDb.find_by_id(conf.anonymous, true)
        set_consumer(anonymous)
        Logger.getInstance(ngx):logInfo({msg = "Escher authentication skipped."})
    end

end

return EscherHandler
