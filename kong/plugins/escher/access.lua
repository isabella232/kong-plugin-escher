local cjson = require "cjson"
local constants = require "kong.constants"
local ConsumerDb = require "kong.plugins.escher.consumer_db"
local Crypt = require "kong.plugins.escher.crypt"
local EscherWrapper = require "kong.plugins.escher.escher_wrapper"
local KeyDb = require "kong.plugins.escher.key_db"
local Logger = require "logger"
local responses = require "kong.tools.responses"

local Access = {}

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

local function get_transformed_response(template, response_message)
    return cjson.decode(string.format(template, response_message))
end

local function collect_request_for_auth()
    ngx.req.read_body()

    return {
        ["method"] = ngx.req.get_method(),
        ["url"] = ngx.var.request_uri,
        ["headers"] = ngx.req.get_headers(),
        ["body"] = ngx.req.get_body_data()
    }
end

local function anonymous_passthrough_is_enabled(plugin_config)
    return plugin_config.anonymous ~= nil
end

function Access.execute(conf)
    local crypt = Crypt(conf.encryption_key_path)
    local key_db = KeyDb(crypt)
    local escher = EscherWrapper(key_db)

    local request = collect_request_for_auth()

    local escher_key, err = escher:authenticate(request)

    if escher_key then
        local consumer = ConsumerDb.find_by_id(escher_key.consumer_id)

        set_consumer(consumer, escher_key)
        Logger.getInstance(ngx):logInfo({msg = "Escher authentication was successful.", ["x-ems-auth"] = request.headers['x-ems-auth']})
    elseif anonymous_passthrough_is_enabled(conf) then
        local anonymous = ConsumerDb.find_by_id(conf.anonymous, true)
        set_consumer(anonymous)
        Logger.getInstance(ngx):logWarning({msg = "Escher authentication skipped.", ["x-ems-auth"] = request.headers['x-ems-auth']})
    else
        local status_code = conf.status_code

        Logger.getInstance(ngx):logWarning({status = status_code, msg = err, ["x-ems-auth"] = request.headers['x-ems-auth']})

        return responses.send(status_code, get_transformed_response(conf.message_template, err))
    end
end

return Access
