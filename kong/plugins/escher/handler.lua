local constants = require "kong.constants"
local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"

local EscherHandler = BasePlugin:extend()

EscherHandler.PRIORITY = 1007

local function set_consumer(consumer, api_key)
    ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
    ngx.ctx.authenticated_consumer = consumer

    if api_key then
        ngx.req.set_header(constants.HEADERS.CREDENTIAL_USERNAME, api_key)
        ngx.req.set_header(constants.HEADERS.ANONYMOUS, nil)
        ngx.ctx.authenticated_credential = api_key
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
        local api_key, err = escher:authenticate()
        ngx.log(ngx.ERR, 'hello')
        if not api_key then
            return responses.send(401, err)
        end

        set_consumer({id = '7d11d371-1175-4159-b6b4-d77f2015e396', custom_id = nil, username = 'test'}, api_key)

        ngx.req.set_header(constants.HEADERS.ANONYMOUS, nil)
    elseif conf.anonymous == nil then
        local error_message = "X-EMS-AUTH header not found!"
        return responses.send(401, error_message)
    else
        ngx.req.set_header(constants.HEADERS.ANONYMOUS, true)

    end

end

return EscherHandler
