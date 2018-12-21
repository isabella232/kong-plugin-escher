local cjson = require "cjson"
local constants = require "kong.constants"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local Crypt = require "kong.plugins.escher.crypt"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local RequestElements = require "kong.plugins.escher.request_elements"
local KeyDb = require "kong.plugins.escher.key_db"
local Logger = require "logger"
local responses = require "kong.tools.responses"

local Access = {}

local function set_consumer(consumer)
    ngx.req.set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
    ngx.req.set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)

    ngx.ctx.authenticated_consumer = consumer
end

local function set_authenticated_access(credentials)
    ngx.req.set_header(constants.HEADERS.CREDENTIAL_USERNAME, credentials.key)
    ngx.req.set_header(constants.HEADERS.ANONYMOUS, nil)

    ngx.ctx.authenticated_credential = credentials
end

local function set_anonymous_access()
    ngx.req.set_header(constants.HEADERS.ANONYMOUS, true)
end

local function anonymous_passthrough_is_enabled(plugin_config)
    return plugin_config.anonymous ~= nil
end

local function get_transformed_response(template, response_message)
    return cjson.decode(string.format(template, response_message))
end

function Access.execute(conf)
    local crypt = Crypt(conf.encryption_key_path)
    local key_db = KeyDb(crypt)
    local escher = EscherWrapper(key_db)

    local request = RequestElements(ngx):collect()

    local credentials, err = escher:authenticate(request)

    if credentials then
        Logger.getInstance(ngx):logInfo({ msg = "Escher authentication was successful.", ["x-ems-auth"] = request.headers['x-ems-auth'] })

        local consumer = ConsumerDb.find_by_id(credentials.consumer_id)

        set_consumer(consumer)

        set_authenticated_access(credentials)

        return
    end

    if anonymous_passthrough_is_enabled(conf) then
        Logger.getInstance(ngx):logWarning({ msg = "Escher authentication skipped.", ["x-ems-auth"] = request.headers['x-ems-auth'] })

        local anonymous = ConsumerDb.find_by_id(conf.anonymous)

        set_consumer(anonymous)

        set_anonymous_access()

        return
    end

    local status_code = conf.status_code

    Logger.getInstance(ngx):logWarning({status = status_code, msg = err, ["x-ems-auth"] = request.headers['x-ems-auth'] })

    return responses.send(status_code, get_transformed_response(conf.message_template, err))
end

return Access
