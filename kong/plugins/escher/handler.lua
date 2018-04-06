local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local ConsumerDb = require "kong.plugins.escher.consumer_db"

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

    local escher_header_string = ngx.req.get_headers()["X-EMS-AUTH"]

    if escher_header_string then
        local escher = EscherWrapper(ngx)
        local escher_key, err = escher:authenticate()

        if not escher_key then
            return responses.send(401, err)
        end

        local consumer = ConsumerDb.find_by_id(escher_key.consumer_id)

        set_consumer(consumer, escher_key)
    elseif conf.anonymous == nil then
        local error_message = "X-EMS-AUTH header not found!"
        return responses.send(401, error_message)
    else
        local anonymous = ConsumerDb.find_by_id(conf.anonymous, true)
        set_consumer(anonymous)
    end

end

return EscherHandler
